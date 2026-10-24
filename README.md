# 大肥鱼控制台 v0.2 · KernelSU 适配版（Android 原生 App 工程）🐋

这是一个 **独立 Android 控制台的可编译源码工程**，不是已编译的 APK。构建后 App 直接用 Root shell 管理现有 Ubuntu chroot，不调用 Termux 的 Activity，也不主动创建 Termux 最近任务卡片。

## 适用于你的部署

- Android Root（已适配 KernelSU）；已安装 `/data/local/chroot/ubuntu`。
- 从 Termux 已验证的 BusyBox 复制一份到 `/data/adb/whale-controller/busybox`，避免独立 APK 的 KernelSU mount namespace 无法访问 Termux 私有路径。首次部署执行：
  ```sh
  su -c 'mkdir -p /data/adb/whale-controller && chmod 700 /data/adb/whale-controller && cp /data/data/com.termux/files/usr/bin/busybox /data/adb/whale-controller/busybox && chmod 700 /data/adb/whale-controller/busybox && /data/adb/whale-controller/busybox --help >/dev/null && echo BUSYBOX_READY'
  ```
  如果原文件因 Root namespace 不可见，请先从 Termux 内运行上述命令，不要从 APK 内复制。
- Ubuntu 中已有经你验证的一键脚本 `/root/start-whale.sh`、`/root/stop-whale.sh`。
- Linux QQ / SnowLuma / K0nd1us QQ Agent 0.4 均已部署。
- App **不包含** QQ、SnowLuma、Agent、聊天数据、账号或 API Key。

## KernelSU 专项说明（v0.2）

- **Root 授权**：应用使用 `su -c`，由 KernelSU 的「超级用户」页面授权该 APK，不需要也不应该另外安装 Magisk。
- **开机自启**：使用官方支持的 `boot-completed.d`；仍然默认关闭，必须在 App 内主动启用。
- **首次解锁**：Ubuntu 依赖的 Termux BusyBox 位于 `/data/data`。手机重启后必须完成首次解锁才能访问相关文件；脚本最多等待约 60 分钟。
- **旧版迁移**：启用 v0.2 自启时，会删除标有 `# WHALE_CONTROLLER_MANAGED` 的 v0.1 同名 `service.d` 脚本，避免重复启动；不会删除其他开机脚本。
- **守护与消息**：仍然只能确认端口和进程，不等于 QQ Hook、OneBot 消息同步已验证。建议先关闭 Termux 旧监控，再在 App 中开启新监控。

## 编译成 APK

方式 A：在装有 Android Studio / Android SDK 35、JDK 17 的构建环境中打开本目录，同步项目并执行 `assembleDebug`。项目使用 Gradle 8.9 + Android Gradle Plugin 8.7.3。APK 输出位置：`app/build/outputs/apk/debug/app-debug.apk`。项目不附带 Gradle Wrapper JAR，需使用 Android Studio 安装的 Gradle 或系统 Gradle 8.9。

方式 B（手机上通过 GitHub 构建，无需自己的电脑）：把**本源码项目**上传到你的 GitHub 仓库（不上传 QQ 配置、Token 或聊天记录），在仓库 Actions 页面选择 `Build 大肥鱼控制台 APK` 并点 Run workflow，完成后下载 Artifact 内的 `app-debug.apk` 安装。GitHub Actions 只负责构建 APK，大肥鱼运行时不依赖云服务器。

注意：Debug APK 由构建环境签名，不适合作为公开分发的正式签名版；后续更新必须保持相同签名，否则需卸载旧 App（Root 脚本与 Ubuntu 数据不随 App 卸载而清空）。

## 第一次打开

1. 安装 APK，打开「大肥鱼控制台」。
2. 在 KernelSU 管理器 → 超级用户中，仅向你自己构建、核对过的 APK 授予 Root。App 会把其管理脚本复制到 `/data/adb/whale-controller/controller.sh`，默认权限 0700。
3. 先点「刷新运行状态」，确认 Root、chroot 路径正常，再点「启动大肥鱼」。
4. 分别检查 6081、5099、3210 三个端口，并用另一个 QQ 账号做消息发送验证。
5. 后台守护默认开启，但**只有点启动且存在 `wanted` 标志时才进行自动恢复**。手动停止将清除该标志，不会被守护再次启动。
6. 「后台隐藏」只隐藏本 App 的最近任务卡片。仍可点桌面图标打开 App，不会隐藏 Termux 之前已打开的卡片。
7. 「开机自启」默认关闭。建议完成冷启动和一键停止测试后再打开。使用 KernelSU 官方支持的 `/data/adb/boot-completed.d/` 开机脚本，不依赖 Magisk。首次开机需解锁手机以访问 Termux 数据。

## 与原 Termux:Widget 守护器的关系（非常重要）

你此前安装的 Termux 启动包已经有一个每 120 秒轮询的 `~/.whale/watch.pid` 守护器。**不要同时运行两个守护器**。切换到本 App 前，在普通 Termux 内运行以下命令（无需 Root，勿在 Ubuntu 中执行）：

```bash
rm -f ~/.whale/boot-enabled
touch ~/.whale/stop.flag
if [ -f ~/.whale/watch.pid ]; then
  PID=$(cat ~/.whale/watch.pid)
  case "$PID" in *[!0-9]*|'') ;; *) kill -TERM "$PID" 2>/dev/null || true ;; esac
fi
```

这只关闭 Termux 的旧监控，不卸载 Termux，也不删除 QQ Agent 的人格、插件、聊天和备份。随后才在本 App 中启用新的守护。

## 服务恢复流程

- **启动**：通过 Root 挂载 `/dev`、`/dev/pts`、`/proc`、`/sys` 到 chroot，然后调用已有的 `/root/start-whale.sh`。
- **守护**：后台 Root shell 独立存在，不占用 Termux 最近任务卡片。每 90 秒检查；连续两次失败才调用既有脚本恢复。
- **停止**：先取消“期望运行”状态、终止守护，再调用 `/root/stop-whale.sh`。不会主动删除持久数据。
- **开机自启**：把受控脚本安装到 `/data/adb/boot-completed.d/99-whale-controller.sh`，由 KernelSU 在 boot completed 阶段执行。脚本等待 Termux 数据和 Ubuntu 可访问后再启动，最多等待约 60 分钟。

## 重要局限

- “后台隐藏”只影响该控制台的最近任务卡片，**不是内核级保活**，也不会隐藏 KernelSU 授权提示或系统可能要求的后台通知。
- 守护只检测 Linux QQ 进程与三个 HTTP 端口，**不等于**确认 SnowLuma Hook、OneBot 与模型 API 全部成功。大肥鱼实际是否收发消息需单独测试。
- 若系统强制杀掉 Root 进程，守护可能失效。Root / KernelSU 开机启动的兼容性取决于手机系统版本与 Root 方案。
- QQ 已保存的聊天数据可以持久保留；离线时漏掉的消息是否补收，取决于 QQ、SnowLuma 和 Agent 的能力，不能保证。
- 后台长期运行可能增加耗电与发热，建议定期观察运行情况。
- 使用 Root shell 具有很高权限。请检查 `app/src/main/assets/controller.sh`，不要从陌生来源安装改过的 APK。
- 尚未在 Redmi K90 Ultra 真机执行端到端测试，首次启动先验证 Root 和日志；**不要直接在生产号上盲目启用开机自启。**

## 目录

- `app/src/main/java/cn/whale/controller/MainActivity.java`：独立原生 Android UI、后台隐藏与 Root 控制按钮。
- `app/src/main/assets/controller.sh`：Root 控制、chroot、后台守护和 KernelSU 开机脚本。
- `.github/workflows/android-apk.yml`：可在 GitHub Actions 构建 Debug APK。

## 排错

Root 管理脚本在 `/data/adb/whale-controller/`，日志在同目录 `watch.log` 和 `boot.log`。Ubuntu 的服务日志沿用你现有的 `/tmp/snowluma.log`、`/tmp/qqagent.log`。控制台页面提供「查看守护日志」按钮。

如果页面显示 `su: inaccessible` 或 Root 权限被拒，请检查 KernelSU 是否向本 App 授权，不要把 Root 命令改成 Termux 前台执行来掩盖问题。

## 卸载前清理

先在 App 中关闭「开机自启」，点击「关闭大肥鱼」，然后再卸载 APK。**直接卸载 APK 不会自动删除 `/data/adb/boot-completed.d` 中由 KernelSU 安装的开机脚本**。需要手动清理时，先确认没有其他服务依赖该脚本，再在具有 Root 权限的终端执行：

```sh
su -c '/system/bin/sh /data/adb/whale-controller/controller.sh boot-off'
su -c '/system/bin/sh /data/adb/whale-controller/controller.sh watch-off'
```

不要清理 `/data/local/chroot/ubuntu`，否则会破坏原有的大肥鱼环境。
