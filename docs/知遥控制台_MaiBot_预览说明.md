# 知遥控制台（MaiBot 预览版）

本分支将原 Android Root 控制台改为独立的 **知遥控制台**，不再管理 QQAgent/QQAgentPlus。

## 范围

- MaiBot：从 Ubuntu chroot 中启动、停止、检测、守护和查看日志。
- SnowLuma / Linux QQ：优先复用目前已启动的服务，**不会再启动 QQAgent，也不会对外部进程执行停止命令**。
- KernelSU Root：后台运行；不需要保持 Termux 活跃。
- 新包名 `cn.zhiy.controller`，可和旧版 App 并存，方便验证后再卸载旧控制台。
- 独立状态路径：`/data/adb/zhiy-controller`；不会读取或清空 QQAgent 旧目录，也不会改动 MaiBot 的人格和记忆文件。
- 旧探索日记、QQAgent 3210 面板以及旧脚本 `start-whale.sh` 已从新 App 中去除。

## 当前限制（务必看）

**本预览版不保证在手机重启后自动拉起 Linux QQ 和 SnowLuma。**
因为这两个服务在每台设备的实际启动方式、登录态、DISPLAY、noVNC 以及脚本路径可能不同。
目前仅在服务已在线时复用它们，同时由 Root 启动 MaiBot；因此开机自启开关**只完整覆盖 MaiBot**。

要做真正的一键启动/关停全部三个服务，还需要对照手机上现有的启动命令，单独迁移 QQ 与 SnowLuma，避免碰到旧 QQAgent。

**重要：** 新 App 的「停止知遥」只停止由新控制台启动的 MaiBot，不会误杀已运行的 QQ 或 SnowLuma。如果 MaiBot 是外部手工启动的，也不会强行停止。

## 使用前确认

1. KernelSU 的 BusyBox：`/data/adb/ksu/bin/busybox`
2. Ubuntu chroot：`/data/local/chroot/ubuntu`
3. MaiBot 工作目录：默认 `/root/maibot-whale`
4. MaiBot 命令：默认 `/root/.local/bin/maibot`
5. MaiBot WebUI：默认 `http://127.0.0.1:8001`
6. SnowLuma WebUI：尝试 `5099` 或 `3000`，不涉及 Token。

实际 MaiBot 位置不同，可以修改 Root 私有文件：
`/data/adb/zhiy-controller/config.sh`

## 测试步骤

1. **先在旧控制台关闭后台守护与开机自启**，但不用卸载旧 App，免得它尝试拉起 QQAgent。
2. 安装知遥控制台 APK，在 KernelSU 授权 Root。
3. 打开后先点「刷新运行状态」，核对 MaiBot / SnowLuma / QQ 状态。
4. 点「启动知遥」，测试 WebUI 和 QQ 私聊。
5. 点「关闭知遥」，确认只有由新控制台拉起的 MaiBot 被停止，SnowLuma 与 QQ 不受影响。
6. 再启用后台守护，做锁屏测试。开机自启应在核对 Linux QQ 和 SnowLuma 独立启动流程后启用。

## 诊断

```sh
su -c 'sh /data/adb/zhiy-controller/controller.sh status'
su -c 'sh /data/adb/zhiy-controller/controller.sh logs-maibot'
su -c 'sh /data/adb/zhiy-controller/controller.sh logs'
```

日志保存在 `/data/adb/zhiy-controller/`；包含启动异常细节，不要公开分享未脱敏的文件。

## 构建

在 GitHub Actions 中使用本仓库的 `Build 知遥控制台 APK` 工作流。
调试 APK 的签名可能变动；不要为安装控制台而删除 Ubuntu 或 MaiBot 数据。
