# MPV Lightweight Preload API - 设计文档

## 概述

这是一个为 MPV 实现的轻量级视频预加载系统，允许在播放前预先缓存视频数据，从而实现更快的播放启动。

### 核心特点

- **轻量级**：不创建完整的 `mpv_handle`，只使用 demuxer 层
- **独立上下文**：每个预加载条目有自己的 `mpv_global` 
- **无缝交接**：预加载的 demuxer 可以直接被播放器使用
- **可配置缓冲**：支持自定义缓存大小和预读秒数

---

## 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                    Dart 层                               │
│  MediaKitPreloader ──► PreloadInfo (status, progress)   │
└─────────────────────────┬───────────────────────────────┘
                          │ FFI
┌─────────────────────────▼───────────────────────────────┐
│                    C API 层                              │
│  mpv_preload_start()   mpv_preload_get_info()          │
│  mpv_preload_cancel()  mpv_preload_clear_all()         │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│               preload_cache (全局缓存)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ preload_entry│  │ preload_entry│  │ preload_entry│   │
│  │ - url        │  │ - url        │  │ - url        │   │
│  │ - global     │  │ - global     │  │ - global     │   │
│  │ - demuxer    │  │ - demuxer    │  │ - demuxer    │   │
│  │ - cancel     │  │ - cancel     │  │ - cancel     │   │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────┘
```

---

## 文件结构

| 文件 | 描述 |
|-----|------|
| `include/mpv/preload.h` | 公共 API 头文件，定义导出函数 |
| `player/preload.h` | 内部头文件，声明 `mpv_preload_get_demuxer()` |
| `player/preload.c` | 核心实现 |
| `player/loadfile.c` | 修改以支持预加载 demuxer 复用 |

---

## MPV 与 FFmpeg 架构

### 层次关系

```
┌────────────────────────────────────────────┐
│              MPV (媒体播放器)               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │ Demuxer  │ │ Decoder  │ │ Renderer │   │
│  │ (解封装) │ │ (解码)   │ │ (渲染)   │   │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘   │
└───────┼────────────┼────────────┼──────────┘
        │            │            │
        ▼            ▼            │
┌───────────────────────────────┐ │
│        FFmpeg (libav*)        │ │
│  libavformat   libavcodec     │ │
│  (解封装)      (解码)         │ │
└───────────────────────────────┘ │
                                  ▼
                         GPU / OpenGL / Metal
```

### 轻量级预加载只使用 Demuxer 层

| 组件 | 完整 Player | 轻量级预加载 |
|-----|:-----------:|:-----------:|
| 网络连接 | ✅ | ✅ |
| 容器解析 (格式探测) | ✅ | ✅ |
| Packet 缓存 | ✅ | ✅ |
| 视频解码器 | ✅ | ❌ |
| 音频解码器 | ✅ | ❌ |
| GPU 硬件加速 | ✅ | ❌ |
| 渲染管线 | ✅ | ❌ |
| 音频输出 | ✅ | ❌ |

**内存占用对比**：
- 完整 Player: ~50-100MB
- 轻量级预加载: ~15MB（主要是 packet 缓存）

---

## Stats 模块的特殊处理

### 为什么 Stats 需要特殊处理？

`stats` 是 MPV 全局性能统计系统，有严格的清理顺序要求：

```
mpv_global
    └── stats_base (注册中心)
            └── list: [stats_ctx, stats_ctx, ...]
                         ↑
              demuxer 的统计 (注册到 stats_base)
```

**问题**：`stats_destroy` 有 assertion `mp_assert(!stats->list.head)`，要求所有 `stats_ctx` 必须先销毁。

**解决方案**：预加载不需要性能统计，所以不初始化 stats：
- `global->stats = NULL`
- `stats_ctx_create` 返回 NULL
- demuxer 正常工作，只是没有统计功能

---

## 预加载技术路线对比

### 竞品架构 (网络层预加载)

竞品在**数据层**做预加载，特点：
- 预加载模块连接到 `FFmpegMediaStream`（抽象层）
- 依赖专门的 Cache 模块（两级 Cache、数据索引）
- 网络模块支持预连接、多连接策略

### 两种技术路线对比

| 维度 | 网络层预加载 (竞品) | Demuxer 层预加载 (我们) |
|-----|:------------------:|:----------------------:|
| **缓存位置** | 网络/Cache 层 | Demuxer 层 |
| **缓存内容** | 原始二进制数据 | 已解封装的 Packet |
| **启动延迟** | 需要解封装 | 零解封装延迟 |
| **实现复杂度** | 高（需要 Cache 系统） | 低（复用 MPV demuxer） |
| **跨播放器复用** | ✅ 可复用 | ❌ 绑定 MPV |
| **内存效率** | 更高（原始数据） | 较低（已解析数据） |
| **状态转移** | 简单（无状态） | 复杂（需转移 demuxer） |

### 缓存生命周期对比

| 特性 | 我们的方案 (Demux 层) | 竞品方案 (数据层) |
|-----|:---------------------:|:-----------------:|
| **缓存存储** | 内存 (demuxer buffer) | 磁盘 (两级 Cache) |
| **生命周期** | demuxer 销毁即失效 | 可跨会话持久化 |
| **播放后** | 缓存随 player 释放 | 缓存保留 |
| **复杂度** | 简单，无需额外模块 | 复杂，需要索引管理 |
| **适用场景** | 短视频列表、即看即播 | 长视频、离线缓存 |

> [!NOTE]
> MPV 支持 `--cache-on-disk` 选项写入磁盘，但缓存文件在媒体关闭时会被删除，
> **不能实现真正的跨会话持久化**。如果需要持久缓存，需要在网络层实现自定义缓存代理。

### 设计选择

我们选择 **Demuxer 层预加载** 的原因：
1. **更快启动**：跳过解封装步骤，直接使用已解析的 Packet
2. **实现简单**：复用 MPV 现有 demuxer，无需构建单独的 Cache 系统
3. **与 MPV 深度集成**：preloaded demuxer 可直接被 loadfile.c 使用

### 注意：网络层预加载的格式处理

竞品虽然在网络层做缓存，但仍需处理格式差异：
- **HLS/m3u8**：需要解析索引、管理分片下载、处理加密密钥
- **MP4**：需要处理 moov 原子位置（前置/后置）
- **加密视频**：需要单独的密钥管理

从架构图的 "Cache协议" 标注推测，他们可能通过 FFmpeg 自定义协议 (`avio`) 拦截网络请求，让 FFmpeg 仍负责格式解析，但需要 HLS 模块做优化。我们的方案**完全不感知格式**，全部交给 MPV/FFmpeg 处理。

## 公共 C API

### 数据结构

```c
// 预加载选项
typedef struct mpv_preload_options {
    int64_t max_bytes;      // 缓存大小 (默认 10MB)
    double readahead_secs;  // 预读秒数 (默认 10s)
} mpv_preload_options;

// 预加载状态
typedef enum mpv_preload_status {
    MPV_PRELOAD_STATUS_NONE = 0,     // 无预加载
    MPV_PRELOAD_STATUS_LOADING = 1,  // 正在加载
    MPV_PRELOAD_STATUS_READY = 2,    // 可用
    MPV_PRELOAD_STATUS_ERROR = 3,    // 错误
} mpv_preload_status;

// 预加载信息
typedef struct mpv_preload_info {
    mpv_preload_status status;
    int64_t cached_bytes;       // 已缓存字节数
    int64_t target_bytes;       // 目标缓存大小
    double buffered_secs;       // 已缓存秒数
    bool eof_cached;            // 是否已缓存完整文件
} mpv_preload_info;
```

### API 函数

```c
// 开始预加载
int mpv_preload_start(const char *url, const mpv_preload_options *opts);

// 获取简单状态
mpv_preload_status mpv_preload_get_status(const char *url);

// 获取详细信息
int mpv_preload_get_info(const char *url, mpv_preload_info *info);

// 取消预加载
int mpv_preload_cancel(const char *url);

// 清除所有预加载
void mpv_preload_clear_all(void);

// 回调类型：预加载状态变化时调用
typedef void (*mpv_preload_callback)(const char *url, mpv_preload_status status);

// 设置全局回调（从后台线程调用）
void mpv_preload_set_callback(mpv_preload_callback callback);

// 内部 API: 获取 demuxer 供播放器使用
struct demuxer *mpv_preload_get_demuxer(const char *url);
```

### 回调触发时机

| 状态 | 值 | 触发条件 |
|-----|:--:|---------|
| READY | 2 | demuxer 可用，可以开始播放 |
| CACHED | 4 | 缓存达到目标 bytes 或整个文件已缓存 |
| ERROR | 3 | 打开失败 |

---

## Dart Callback 使用

```dart
preloader.stream.listen((event) {
  if (event.isReady) {
    print('可以播放了');
  } else if (event.isCached) {
    print('缓存目标达成！');
  }
});
```

---

## 关键实现细节

### 1. Minimal mpv_global 初始化

创建一个最小化的 `mpv_global` 上下文，只包含 demuxer 必需的组件：

```c
static struct mpv_global *create_minimal_global(int64_t max_bytes, double readahead_secs)
{
    struct mpv_global *global = talloc_zero(NULL, struct mpv_global);
    
    global->log = mp_null_log;                    // 静默日志
    global->config = m_config_shadow_new(&mp_opt_root);  // 配置系统
    
    stats_global_init(global);        // 统计系统 (demux 需要)
    demux_packet_pool_init(global);   // Packet 内存池 (关键!)
    
    // 设置 demux 选项
    // ...
    
    return global;
}
```

> **关键点**: `demux_packet_pool_init()` 必须调用，否则 demuxer 释放时会因为 NULL mutex 崩溃。

### 2. Stream 选择

Demuxer 只会为 "selected" 的 stream 读取数据：

```c
// 选择所有 video 和 audio streams
int num_streams = demux_get_num_stream(entry->demuxer);
for (int i = 0; i < num_streams; i++) {
    struct sh_stream *sh = demux_get_stream(entry->demuxer, i);
    if (sh && (sh->type == STREAM_VIDEO || sh->type == STREAM_AUDIO)) {
        demuxer_select_track(entry->demuxer, sh, MP_NOPTS_VALUE, true);
    }
}
```

> **关键点**: 不调用 `demuxer_select_track()`，demuxer 不会缓存任何数据。

### 3. Demuxer 交接

当播放器需要使用预加载的 demuxer 时：

```c
struct demuxer *mpv_preload_get_demuxer(const char *url)
{
    // 设置标志让 preload 线程退出
    // 注意: 不能触发 mp_cancel_trigger()，否则会停止网络读取!
    entry->cancel_requested = true;
    
    // 等待线程退出 (最多 0.5s)
    mp_thread_join(entry->thread);
    
    // 返回 demuxer (所有权转移给调用方)
    struct demuxer *demux = entry->demuxer;
    entry->demuxer = NULL;
    
    return demux;
}
```

> **关键点**: 不能触发 `mp_cancel_trigger()`，因为这会传播到 demuxer 的子 cancel 并停止网络读取。

### 4. loadfile.c 集成

修改 `open_demux_reentrant()` 优先使用预加载的 demuxer：

```c
static void open_demux_reentrant(struct MPContext *mpctx)
{
    char *url = mpctx->stream_open_filename;

    // 首先检查预加载缓存
    struct demuxer *preloaded = mpv_preload_get_demuxer(url);
    if (preloaded) {
        MP_VERBOSE(mpctx, "Using preloaded demuxer for: %s\n", url);
        mpctx->demuxer = preloaded;
        // ... 设置 cancel 父子关系
        return;
    }

    // 正常打开流程
    // ...
}
```

---

## Dart FFI 绑定

### PreloadInfo 类

```dart
class PreloadInfo {
  final MpvPreloadStatus status;
  final int cachedBytes;
  final int targetBytes;
  final double bufferedSecs;
  final bool eofCached;

  bool get isReady => status == MpvPreloadStatus.ready;
  bool get hasData => status == MpvPreloadStatus.loading || isReady;
  
  double get progress {
    if (eofCached) return 1.0;
    if (targetBytes <= 0) return cachedBytes > 0 ? 1.0 : 0.0;
    return (cachedBytes / targetBytes).clamp(0.0, 1.0);
  }
}
```

### MediaKitPreloader 使用示例

```dart
final preloader = MediaKitPreloader();
await preloader.ensureInitialized();

// 开始预加载
preloader.start('https://example.com/video.mp4',
  options: PreloadOptions(maxBytes: 10 * 1024 * 1024));

// 查询进度
final info = preloader.getInfo('https://example.com/video.mp4');
print('Progress: ${(info.progress * 100).toStringAsFixed(1)}%');
print('Buffered: ${info.bufferedSecs.toStringAsFixed(1)}s');

// 播放时自动使用预加载数据
player.open(Media('https://example.com/video.mp4'));
// 首次播放启动时间: ~130ms (vs 正常 ~2-3s)
```

---

## 性能对比

| 场景 | 首帧时间 | 内存占用 |
|-----|---------|---------|
| 无预加载 | ~2-3s | - |
| 完整 Player 预加载 | ~100ms | ~50MB/个 |
| **轻量级 Demuxer 预加载** | **~130ms** | **~15MB/个** |

---

## 遇到的问题与解决方案

| 问题 | 原因 | 解决方案 |
|-----|------|---------|
| `stats_ctx_create` 崩溃 | `global->stats` 未初始化 | 调用 `stats_global_init()` |
| `mp_time_ns_add` 崩溃 | Timer 子系统未初始化 | 调用 `mp_time_init()` |
| `cancel_destroy` 崩溃 | Demuxer 的 cancel 是 entry->cancel 的子对象 | 不释放 entry->cancel |
| 缓存字节数为 0 | Streams 未被选中 | 调用 `demuxer_select_track()` |
| 播放后无法继续缓冲 | `mp_cancel_trigger()` 停止了网络读取 | 不触发 cancel，只设置标志 |
| `demux_packet_pool_prepend` 崩溃 (NULL mutex) | `packet_pool` 未初始化 | 调用 `demux_packet_pool_init()` |

---

## 文件修改清单

### MPV 代码修改

| 文件 | 修改类型 | 描述 |
|-----|---------|------|
| `include/mpv/preload.h` | 新建 | 公共 API 头文件 |
| `player/preload.h` | 新建 | 内部头文件 |
| `player/preload.c` | 新建 | 核心实现 (~450 行) |
| `player/loadfile.c` | 修改 | 添加预加载 demuxer 检查 |
| `meson.build` | 修改 | 添加 preload.c 到构建 |

### Dart 代码修改

| 文件 | 修改类型 | 描述 |
|-----|---------|------|
| `media_kit/lib/generated/libmpv/preload_bindings.dart` | 新建/修改 | FFI 绑定 |
| `media_kit/lib/src/preload/media_kit_preloader.dart` | 新建/修改 | Dart API 封装 |
| `media_kit_test/lib/tests/12.preload_test.dart` | 修改 | 测试页面 |

---

## 限制与已知问题

1. ~~**资源泄漏**: 当 demuxer 被转移时，原始的 `mpv_global` 和 `mp_cancel` 不会被释放~~ **已修复！**
2. **最大条目数**: 固定为 4 个并发预加载
3. **平台支持**: 目前只在 macOS 上测试
4. **释放延迟**: media_kit 的 `dispose()` 有 5 秒延迟，导致资源不会立即释放

---

## 内存泄漏修复 (2026-01-18)

### 问题
预加载创建的 `mpv_global` 包含 `stats_base`，而 demuxer 内部的 `stats_ctx` 注册到了这个 `stats_base`。
当 demuxer 被释放时，如果 `stats_ctx` 还在列表中就释放 `stats_base`，会触发 assertion 失败。

### 解决方案

1. **修改 `stats_ctx_create`** (`common/stats.c`):
   - 当 `global->stats` 为 NULL 时返回 NULL（而不是 assert）
   - 添加 NULL ctx 检查到 `register_thread`

2. **修改 `create_minimal_global`** (`player/preload.c`):
   - 不调用 `stats_global_init()` - 预加载不需要 stats
   - 使用 `talloc_steal(demux, global)` 让 global 跟随 demuxer 释放

### 验证结果

✅ 测试证明 cleanup 正确工作:
```
[loadfile] kill_demuxers_reentrant called with 1 demuxers
[preload] Global 0x... being freed (cleanup working correctly)
```

---

## 未来改进方向

1. ~~正确管理 `mpv_global` 生命周期，消除资源泄漏~~ **已完成**
2. 添加预加载优先级和智能驱逐策略
3. 支持更多平台 (iOS, Android, Windows, Linux)
4. ~~添加回调机制，而不是轮询状态~~ **已完成** (2026-01-18)

