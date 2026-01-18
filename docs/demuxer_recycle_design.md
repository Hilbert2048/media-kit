# Demuxer 回收机制设计方案

## 问题背景

当前流程中，demuxer 从预加载队列 detach 后被播放器使用，播放器销毁时 demuxer 也随之销毁。
这导致缓存生命周期短，用户返回后需要重新下载。

## 目标

允许播放器销毁时将 demuxer 归还到预加载队列，延长缓存生命周期。

---

## 设计方案

### 状态机变更

```
原状态: NONE → LOADING → READY → CACHED → (detach) → 销毁

新状态: NONE → LOADING → READY → CACHED → DETACHED → (recycle) → CACHED
                                              ↓
                                            销毁
```

新增 `MPV_PRELOAD_STATUS_DETACHED` 状态：
- demuxer 被 player 取走，entry 保留 URL 用于匹配
- entry 的 global/cancel 字段设为 NULL（已通过 talloc_steal 转移到 demuxer）
- 可以被 recycle 回来

### 核心改动

#### 1. preload.h - 新增状态和 API

```c
// 新状态
MPV_PRELOAD_STATUS_DETACHED = 5,  // demuxer 被取走，可回收

// 新增 API
int mpv_preload_recycle(const char *url, struct demuxer *demuxer);
```

#### 2. preload.c - get_demuxer 保留 entry

```c
// 变更：不清除 entry，只标记状态
entry->demuxer = NULL;  // 取走 demuxer
entry->status = MPV_PRELOAD_STATUS_DETACHED;
entry->global = NULL;   // 已 talloc_steal 到 demuxer
entry->cancel = NULL;   // 已 talloc_steal 到 demuxer
// entry->url 保留，用于 recycle 匹配
```

#### 3. preload.c - recycle 实现

```c
int mpv_preload_recycle(const char *url, struct demuxer *demuxer) {
    // 查找 DETACHED 状态的 entry
    struct preload_entry *entry = find_entry_locked(url);
    if (!entry || entry->status != MPV_PRELOAD_STATUS_DETACHED)
        return -1;
    
    // 归还 demuxer
    entry->demuxer = demuxer;
    entry->status = MPV_PRELOAD_STATUS_CACHED;
    entry->create_time = time(NULL);  // 刷新 LRU 时间
    
    // Note: entry->global/cancel 保持 NULL
    // 它们通过 talloc 仍由 demuxer 管理
    
    invoke_callback(entry);
    return 0;
}
```

#### 4. core.h - 新增 preload_url 字段

```c
typedef struct MPContext {
    // ...
    char *preload_url;  // If non-NULL, demuxer came from preload queue
    // ...
} MPContext;
```

#### 5. loadfile.c - 使用预加载 demuxer

```c
static void open_demux_reentrant(struct MPContext *mpctx) {
    struct demuxer *preloaded = mpv_preload_get_demuxer(url);
    if (preloaded) {
        mpctx->demuxer = preloaded;
        mpctx->preload_url = talloc_strdup(mpctx, url);  // 保存 URL
        if (preloaded->cancel)
            mp_cancel_set_parent(preloaded->cancel, mpctx->playback_abort);
        return;
    }
    // ... 正常流程
}
```

#### 6. loadfile.c - uninit_demuxer 回收逻辑

```c
static void uninit_demuxer(struct MPContext *mpctx) {
    struct demuxer *recycled_demuxer = NULL;
    
    if (mpctx->demuxer && mpctx->preload_url) {
        struct demuxer *demuxer_to_recycle = mpctx->demuxer;
        
        // 清理 cancel parent（player 销毁后会失效）
        if (mpctx->demuxer->cancel)
            mp_cancel_set_parent(mpctx->demuxer->cancel, NULL);
        
        // 尝试回收
        if (mpv_preload_recycle(mpctx->preload_url, mpctx->demuxer) == 0) {
            recycled_demuxer = demuxer_to_recycle;  // 记录，避免被销毁
            mpctx->demuxer = NULL;
        }
        talloc_free(mpctx->preload_url);
        mpctx->preload_url = NULL;
    }
    
    // ... 后续 tracks 清理循环
    for (int i = 0; i < mpctx->num_tracks; i++) {
        // 跳过已回收的 demuxer
        if (track->demuxer == recycled_demuxer) {
            track->demuxer = NULL;
            continue;
        }
        // ... 正常清理
    }
}
```

### 关键实现细节

| 问题 | 解决方案 |
|-----|---------|
| cancel parent 失效 | recycle 前调用 `mp_cancel_set_parent(cancel, NULL)` |
| tracks 仍引用 demuxer | 在 tracks 清理循环中跳过 `recycled_demuxer` |
| entry 的 global/cancel 为 NULL | 回收后 entry 仍可用，demuxer 通过 talloc 管理自己的资源 |
| 初始播放位置 | MPV 正常流程会处理 `opts->play_start`，无需额外处理 |

---

## 使用场景

```dart
// 1. 预加载
preloader.start(url);

// 2. 播放
await player.open(Media(url));  // 内部调用 get_demuxer

// 3. 用户退出播放
player.dispose();  // uninit_demuxer 自动 recycle

// 4. 用户再次进入 - 复用缓存！
await player.open(Media(url, start: Duration.zero));
```

---

## 验证结果

测试 3 次连续播放同一视频：

| 播放 | demuxer 地址 | 结果 |
|:---:|:-----------:|:----:|
| 1 | 0x7561d7950 | ✅ |
| 2 | 0x7561d7950 | ✅ |
| 3 | 0x7561d7950 | ✅ |

每次都复用同一个 demuxer，无需重新下载。

---

## 功能增强 (2024-01)

### 1. 动态 max_entries 配置

支持在初始化时设置预加载队列容量：

```c
// C API
int mpv_preload_set_max_entries(int new_max);  // 必须在首次 preload 前调用
int mpv_preload_get_max_entries(void);
int mpv_preload_get_active_count(void);        // 获取当前使用中的 entry 数量
```

```dart
// Dart API
preloader.setMaxEntries(8);     // 设置最大 8 个，必须在 start() 前
preloader.getMaxEntries();      // 获取当前限制
preloader.getActiveCount();     // 获取当前活跃数量
```

**限制**：
- 只能在首次 preload 前设置
- 范围 1-64（静态数组容量）
- 设置后不可动态修改（避免线程安全问题）

### 2. LOADING 状态等待与复用

当用户快速点击 play 时，即使预加载还在 LOADING 状态（demux_open 进行中），也能等待并复用：

```c
// get_demuxer 中的等待逻辑
if (entry->status == MPV_PRELOAD_STATUS_LOADING && !entry->demuxer) {
    while (entry->status == MPV_PRELOAD_STATUS_LOADING && !entry->demuxer) {
        pthread_cond_wait(&preload_cache.demuxer_ready_cond, &preload_cache.lock);
    }
}
```

**条件变量通知**：
- preload 线程在 demux_open 完成后调用 `pthread_cond_broadcast()`
- get_demuxer 使用 `pthread_cond_wait()` 等待，零延迟唤醒

**应用场景**：HLS 流的 demux_open 较慢，用户可能在预加载未完成时就点击 play，此功能确保等待预加载完成后复用，而不是创建重复的 demuxer。

### 3. 状态查询与测试

测试界面增强：
- 显示 `Max Entries` 和 `Active` 计数
- setMaxEntries 按钮显示操作结果 (OK/FAILED)
- 日志面板自动滚动到底部
