# Android MPV 构建修复指南 (0.41.0)

本文档总结了在 Android 平台上构建 MPV 0.41.0 所需的修改，包括依赖更新和交叉编译问题的修复。

## 1. libxml2 构建 (v2.13.5)
由于 v2.13+ 版本存在交叉编译检测问题，我们从 Autotools 切换到了 Meson 构建 `libxml2`。

**核心变更 ([scripts/libxml2.sh](file:///Users/hilbert/coding/mediakit_workspace/libmpv-android-video-build/buildscripts/scripts/libxml2.sh)):**
- **Meson 配置**: 使用 `meson setup` 并开启 `--default-library=static`，仅启用最小化特性。
- **手动安装**: 由于 `ninja install` 在测试阶段会失败，我们改为手动复制产物。
- **头文件结构**: 将头文件复制到 `$prefix/include/libxml2/libxml/` 以符合 FFmpeg 的预期路径。
- **xmlversion.h**: 增加了逻辑来查找并复制构建目录中 *生成的* `xmlversion.h`。
- **pkg-config 修复**: 手动修补 `libxml-2.0.pc`，设置 `prefix=/` 和 `includedir=${prefix}/include/libxml2`。这修复了使用 `PKG_CONFIG_SYSROOT_DIR` 时的路径解析问题。

## 2. MPV AAudio 兼容性
较旧的 Android NDK 版本（如 r25b）缺少 Android 13 (API 33) 引入的 `AAUDIO_FORMAT_IEC61937` 定义，导致 MPV 0.41.0 编译报错。

**修复 ([scripts/mpv.sh](file:///Users/hilbert/coding/mediakit_workspace/libmpv-android-video-build/buildscripts/scripts/mpv.sh)):**
- 使用 `sed` 命令在 `audio/out/ao_aaudio.c` 中注入缺少的定义：
  ```c
  #ifndef AAUDIO_FORMAT_IEC61937
  #define AAUDIO_FORMAT_IEC61937 13
  #endif
  ```

## 3. Encoders-GPL 变体 (fftools-ffi)
`encoders-gpl` 变体链接了 `fftools-ffi`，用于向 Dart 暴露 FFmpeg CLI 功能。

**修复 ([patch-encoders-gpl.sh](file:///Users/hilbert/coding/mediakit_workspace/libmpv-android-video-build/buildscripts/patch-encoders-gpl.sh)):**
- **Meson 构建注入**: 使用 `sed` 稳健地将 `fftools-ffi` 依赖和源文件注入到 MPV 的 [meson.build](file:///Users/hilbert/coding/mediakit_workspace/mpv/meson.build) 中，适配了 0.41.0 的结构变化。
- **FFmpeg 7.1 兼容性**: `fftools-ffi` 使用了在 FFmpeg 5.0+ 中被移除的 `av_stream_get_end_pts`。我们修补了 `deps/fftools_ffi/ffmpeg.c`，定义了一个兼容性宏：
  ```c
  #define av_stream_get_end_pts(st) ((st)->duration != AV_NOPTS_VALUE ? \
      (st)->start_time + (st)->duration : AV_NOPTS_VALUE)
  ```

## 4. 其他变更
- **MPV Meson 选项**: 移除了已弃用的 `-Dsdl2=disabled` 选项。
- **依赖更新**: 更新 [depinfo.sh](file:///Users/hilbert/coding/mediakit_workspace/libmpv-android-video-build/buildscripts/include/depinfo.sh) 以匹配 Darwin 构建版本。

## 验证
构建已在 CI 环境中成功完成。
- **日志**: [GitHub Actions Run](https://github.com/Hilbert2048/libmpv-android-video-build/actions/runs/12975317789)

## 5. Media-kit 集成
要在 `media-kit` 中使用新的构建产物：

1.  **发布 Release**: 将构建产物 (JARs) 发布到 GitHub Release (例如 `v0.5.0-preload`)。
2.  **更新配置**: 修改 [media_kit_libs_android_video/android/build.gradle](file:///Users/hilbert/coding/mediakit_workspace/media-kit/libs/android/media_kit_libs_android_video/android/build.gradle)：
    -   指向新的 GitHub Release URL。
    -   列出具体的 JAR 产物 (`default` 或 `encoders-gpl`)。
    -   提供 SHA-256 校验和以确保安全。
3.  **NDK 版本**: 确保 Android 应用 (如 `media_kit_test`) 使用有效的已安装 NDK 版本 (如 `26.3.11579264`)，以防默认配置 (如 27) 缺失或损坏。

### 6. 故障排查: libmpv.so 缺失
集成过程中，用户可能会遇到 `Exception: Cannot find libmpv.so`。这通常是“无法加载库”的通用错误。

**根因:**
*   `libmpv.so` (NDK 构建) 依赖于 `libc++_shared.so`。
*   AGP 在使用本地 JAR 依赖时，不会自动打包 `libc++_shared.so`。
*   即使打包了，`libmpv.so` 也必须通过 `DT_NEEDED` 显式声明依赖。

**解决方案 (本次更新已应用):**
1.  **构建脚本**: 更新 `bundle_*.sh`，从 NDK 显式复制 `libc++_shared.so` 到产物中。
2.  **链接器标志**: 更新 [mpv.sh](file:///Users/hilbert/coding/mediakit_workspace/libmpv-android-video-build/buildscripts/scripts/mpv.sh)，添加 `-lc++_shared` 强制在 ELF 头中声明依赖。
3.  **Java 插件 (兜底)**: 更新 [MediaKitLibsAndroidVideoPlugin.java](file:///Users/hilbert/coding/mediakit_workspace/media-kit/libs/android/media_kit_libs_android_video/android/src/main/java/com/alexmercerind/media_kit_libs_android_video/MediaKitLibsAndroidVideoPlugin.java)，通过 `System.loadLibrary` 预加载 `c++_shared`。

**验证:**
使用 `readelf -d libmpv.so | grep NEEDED` 确认 `libc++_shared.so` 在列。

---

## FFmpeg 集成验证 (iOS/macOS)

> [!NOTE]
> 我们已成功在 iOS/macOS 上将 **FFmpeg 7.1** (来自 `fftools-ffi`) 集成到 `media_kit`，使用的是自定义静态构建。

### 1. 架构设计

-   **Native 层**: `libmpv.a` 静态链接 `libfftools-ffi.a`。
    -   暴露 `FFToolsFFIExecuteFFmpeg` 和 `FFToolsFFIInitialize`。
    -   使用 `pthread` 在后台线程运行 FFmpeg CLI。
    -   使用 `Dart_PostCObject` 将日志和返回码发送回 Dart。

-   **Dart 层**:
    -   **纯 FFI 实现**: 无 MethodChannel/PlatformChannel 开销。
    -   **异步执行**: 使用 `ReceivePort` 监听事件，不阻塞 UI。
    -   **内存安全**: 绑定系统原生的 [free](file:///Users/hilbert/coding/mediakit_workspace/mpv/player/client.c#2126-2130) 函数来正确释放 C 分配的内存，避免分配器不匹配问题。
    -   **协议**: 正确映射 [FFToolsMessage](file:///Users/hilbert/coding/mediakit_workspace/media-kit/media_kit/lib/src/ffmpeg/ffmpeg.dart#49-55) (0=返回码, 1=日志, 2=统计)。

### 2. 技术选型：为什么选择 FFI？

我们选择 **Dart FFI** 而不是传统的 **Platform Channels** (如 `ffmpeg_kit_flutter` 所用)，原因如下：

| 特性 | `media_kit` (FFI) | `ffmpeg_kit` (Platform Channels) |
| :--- | :--- | :--- |
| **通信机制** | **直接 C 绑定** (指针零拷贝) | **MethodChannel** (序列化开销) |
| **架构风格** | **统一 Dart 逻辑** (一次编写，到处运行) | **平台特定** (代码隐藏在 Java/ObjC 层) |
| **性能** | **高** (直接内存访问，无 JVM/ObjC 运行时桥接) | **中** (桥接延迟，数据拷贝) |
| **内存管理** | **显式控制** (使用系统 `malloc`/[free](file:///Users/hilbert/coding/mediakit_workspace/mpv/player/client.c#2126-2130)) | **隐式** (依赖平台 GC 机制) |
| **复杂度** | 较高 (必须手动处理内存安全) | 较低 (抽象层处理细节) |

**关键技术洞察**:
我们要实现内存安全，关键在于绑定系统的 [free](file:///Users/hilbert/coding/mediakit_workspace/mpv/player/client.c#2126-2130) 函数 (`DynamicLibrary.process().lookup('free')`) 来释放 FFmpeg C 库分配的内存。这绕过了 Dart 的 GC 和 Dart 特定的分配器，确保与 FFmpeg 原生使用的 `malloc` 100% 兼容，从而彻底消除了 `BUG_IN_CLIENT_OF_LIBMALLOC` 这类崩溃。

### 3. 验证结果

已在 **iPhone 16 Pro Max Simulator** 上测试通过。

#### 测试用例 1: 版本检查
命令: `FFmpeg.execute(['-version'])`
结果:
```text
flutter: [FFmpeg] ffmpeg version 7.1
flutter: [FFmpeg]  Copyright (c) 2000-2023 the FFmpeg developers
flutter: [FFmpeg] configuration:
...
```

#### 测试用例 2: 协议与解复用器
命令: `FFmpeg.execute(['-demuxers'])`
结果:
```text
flutter: [FFmpeg] File formats:
 D. = Demuxing supported
 .E = Muxing supported
 --
flutter: [FFmpeg]  D  aac
flutter: [FFmpeg]  D  hls
flutter: [FFmpeg]  D  mov,mp4,m4a,3gp,3g2,mj2
...
```

### 4. 实施过程中的关键修复

-   **崩溃 Fix (0x0)**: 修复方法：通过 `NativeApi.postCObject` 初始化 `Dart_PostCObject`。
-   **卡死 Fix (无限 Loading)**: 修复方法：修正协议常量 (`0` 是返回码 RET，不是日志 LOG)。
-   **崩溃 Fix (Bad Allocator)**: 修复方法：绑定系统 [free](file:///Users/hilbert/coding/mediakit_workspace/mpv/player/client.c#2126-2130) 而不是使用 `calloc.free` 来释放 C 指针。
-   **崩溃 Fix (Double Free)**: 修复方法：移除 Dart 端的 `argv` 释放逻辑 (C 端已处理)。
