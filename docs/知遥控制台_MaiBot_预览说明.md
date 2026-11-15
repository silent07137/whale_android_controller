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

**v0.1.2 已加入单独的完整冷启动链路**：Xvfb → Fluxbox → VNC/noVNC → SnowLuma → Linux QQ → MaiBot。不会运行旧 `start-whale.sh` 或旧 QQAgent 程序。

- SnowLuma 优先从 `/root/qqagentplus-lab/snowluma-new` 寻找 `index.mjs`，回退到 `/opt/whale/snowluma`。
- Linux QQ：`DISPLAY=:1 /opt/QQ/qq --no-sandbox --disable-gpu --disable-dev-shm-usage`。
- 启动前检查已有进程，复用运行中的组件。启动器自己启动的 SnowLuma、QQ 记录 PID 与进程起始时间，停止时仅处理自己拥有的进程。
- 旧大肥鱼守护/开机自启标记仍存在时阻止新版启动，避免旧 QQAgent 被拉起。
- 后台守护每 90 秒检查所有关键服务，连续两次未通过尝试恢复。

**仍未真机验收**：首次冷启动及重启后能否复用 QQ 登录态、SnowLuma Hook 是否注入、OneBot 是否能真实收发，都需要手机测试。App 显示端口在线不代表 QQ 协议已经正常工作。

**安全提醒**：不自动创建 VNC 密码。若 VNC 密码文件不存在，会跳过 VNC 启动；Root QQ 运行使用 `--no-sandbox` 是旧部署的兼容参数，不应在不可信环境随意扩展。

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
5. 点「停止知遥服务」，确认由新控制台启动的 MaiBot、SnowLuma 和 QQ 能关闭，外部已有实例不会被误杀。
6. 再启用后台守护，做锁屏测试；确认真实 QQ 消息收发、登录态保存后，才打开开机自启并验收重启恢复。

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
