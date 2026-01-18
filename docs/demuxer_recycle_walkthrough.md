# Demuxer Recycle Implementation Walkthrough

## 功能概述

实现了 demuxer 回收机制，允许 player 销毁时将 demuxer 归还到预加载队列，而不是销毁它。这延长了缓存的生命周期，用户返回同一视频时无需重新下载。

---

## 问题与解决方案

### 问题

原设计中，预加载的 demuxer 被 player 使用后，player 销毁时 demuxer 也随之销毁：

```
preload.start() → 队列 → player.open() → detach → player.dispose() → 销毁 ❌
```

### 解决方案

新设计支持 demuxer 回收：

```
preload.start() → 队列 → player.open() → detach → player.dispose() → 回收到队列 ✅
```

---

## 核心改动

### 1. 新增 DETACHED 状态 ([preload.h](file:///Users/hilbert/coding/mpv/include/mpv/preload.h#L57))

```c
MPV_PRELOAD_STATUS_DETACHED = 5,  // Demuxer detached to player, can be recycled
```

### 2. 新增 recycle API ([preload.h](file:///Users/hilbert/coding/mpv/include/mpv/preload.h#L122))

```c
MPV_EXPORT int mpv_preload_recycle(const char *url, struct demuxer *demuxer);
```

### 3. 修改 get_demuxer 保留 entry ([preload.c](file:///Users/hilbert/coding/mpv/player/preload.c#L418))

```c
// 原：清除 entry
// 新：设置 status = DETACHED，保留 entry->url 用于 recycle 匹配
entry->status = MPV_PRELOAD_STATUS_DETACHED;
```

### 4. 实现 recycle 函数 ([preload.c](file:///Users/hilbert/coding/mpv/player/preload.c#L494))

- 查找 DETACHED 状态的 entry
- 将 demuxer 放回 entry
- 设置 status = CACHED
- 触发回调通知

### 5. loadfile.c 集成 ([loadfile.c](file:///Users/hilbert/coding/mpv/player/loadfile.c#L213))

**uninit_demuxer 中的回收逻辑**:
1. 保存 demuxer 指针（用于后续 tracks 清理排除）
2. 清理 cancel parent 关系（防止 dangling pointer）
3. 调用 `mpv_preload_recycle`
4. 在 tracks 清理循环中跳过已回收的 demuxer

**open_demux_reentrant 中的预加载检查**:
1. 调用 `mpv_preload_get_demuxer(url)`
2. 设置 `mpctx->demuxer` 和 `mpctx->preload_url`
3. 建立 cancel parent 关系

### 6. 新增 preload_url 字段 ([core.h](file:///Users/hilbert/coding/mpv/player/core.h#L308))

```c
char *preload_url;  // If non-NULL, demuxer came from preload queue (for recycling)
```

---

## 关键问题与修复

### 问题 1：demuxer->cancel 变成 NULL

**原因**：tracks 清理循环仍然引用已回收的 demuxer，将其添加到 demuxers 列表，被 `kill_demuxers_reentrant` 销毁。

**解决**：在 tracks 清理循环中跳过 `recycled_demuxer`：

```c
if (track->demuxer && track->demuxer == recycled_demuxer) {
    track->demuxer = NULL;
    talloc_free(track);
    continue;
}
```

### 问题 2：第二次使用时 cancel parent 崩溃

**原因**：第一次使用后，demuxer->cancel 的 parent 指向已销毁的 playback_abort。

**解决**：recycle 前清理 cancel parent 关系：

```c
if (mpctx->demuxer->cancel)
    mp_cancel_set_parent(mpctx->demuxer->cancel, NULL);
```

---

## 验证结果

成功测试 **3 次连续播放**同一视频：

| 播放次数 | demuxer 地址 | cancel 状态 | 结果 |
|---------|-------------|-------------|------|
| 第 1 次 | 0x7561d7950 | valid | ✅ |
| 第 2 次 | 0x7561d7950 | valid | ✅ |
| 第 3 次 | 0x7561d7950 | valid | ✅ |

每次都复用同一个 demuxer，无需重新下载。

---

## 潜在风险

| 风险 | 状态 |
|-----|------|
| 内存泄漏 | ⚠️ 需要确认 tracks 清理逻辑完整性 |
| entry 状态不一致 | ⚠️ 需要检查并发访问 |
| cancel 状态异常 | ✅ 已通过清理 parent 解决 |
