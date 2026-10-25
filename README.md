# 🐋 大肥鱼控制台 | Whale Android Controller

> 作者：**[silent07137](https://github.com/silent07137)** · 安卓本机部署 QQ Agent 的实践工程与技术教程  
> 项目状态：**KernelSU / Root 方案已完成真机基础验证**；Shizuku / ADB 方案仍处实验可行性阶段。

本仓库包含一款基于 **Android 原生界面 + KernelSU Root Shell** 的控制台，以及两篇部署技术文档。目标是在 ARM64 安卓手机上管理已有的 **Ubuntu chroot、Linux QQ、SnowLuma 和 K0nd1us/QQ-agent 0.4**，无需通过打开 Termux 终端来启动服务。

**本项目并非 QQ、腾讯、SnowLuma、KernelSU 或 QQ-agent 的官方产品，也不提供这些第三方项目的安装包、账号、令牌、API Key 或私有聊天数据。**

## 📚 部署教程

| 文档 | 适用情况 | 可行性 / 验证状态 |
| --- | --- | --- |
| **[已 Root 安卓完整部署教程](docs/安卓Root部署大肥鱼QQAgent_完整教程.md)** | KernelSU / Root、Ubuntu ARM64 真 chroot | **已实测**：QQ 消息回复、控制台启动、最近任务隐藏和短时后台运行 |
| **[Shizuku（ADB 授权）可行性分析与实验教程](docs/Shizuku_ADB授权部署QQAgent_可行性分析与实验教程.md)** | 无 Root，希望探索 Termux + PRoot | **实验性**：Shizuku 不能提供 Root 权限，SnowLuma 注入与完整收发链路尚未实测成功 |

**Linux QQ 下载请认准官方入口：[QQ Linux 下载页](https://im.qq.com/index/#/linux)**。在网站内选择适合设备架构的 Linux ARM64（aarch64）安装包；该 URL 是网页地址，不是 `.deb` 文件直链。

> 建议：已经 Root 的手机先阅读第一篇；无 Root 设备先阅读第二篇的“可行性声明”，不要把 Shizuku 的 ADB 授权等同于 `su`/Root。

## 📱 控制台功能

- **一键启动 / 停止**：复用 Ubuntu 中已有的 `/root/start-whale.sh` 和 `/root/stop-whale.sh`。
- **运行状态检查**：查看 QQ 进程及 QQ Agent（3210）、SnowLuma（5099）、noVNC（6081）的基础健康状态。
- **后台隐藏**：在「最近任务」中隐藏控制台自己的任务卡片；不会替其他应用隐藏卡片。
- **Root 后台守护**：按健康检测结果尝试恢复服务；“手动停止”不会自动被守护重启。
- **可选开机自启**：使用 KernelSU 的 `/data/adb/boot-completed.d/`；建议通过手动启停和锁屏测试后再开启。
- **管理页面入口**：快捷打开本机 WebUI 和 noVNC。
- **探索日记中心（v0.2）**：一键启动并打开只读探索日记（本机 3222），单独停止日记；自动从 Ubuntu 中已安装的日记获取访问网址，操作日志隐藏访问密钥。
- **可选日记随服务启动**：手动开启后，在本 App 下次「启动大肥鱼」或 KernelSU 开机启动流程中尝试拉起日记，失败不会中断 QQ 主服务。
- **探索组件检查**：显示 `whale-explorer`、`whale-web-reader` 与 `video-watch` 的**安装情况**，不将安装等同于技能启用或调用成功。
- **诊断与日志**：可查看设备总 RAM、可用 RAM、根文件系统可用空间、守护日志、开机日志与日记服务日志（仅本机查看）。

**已经验证的范围**：Root + Ubuntu chroot 服务启动成功、QQ 实际收到并回复消息、控制台最近任务隐藏、约 6 分钟的短时后台运行。**尚不代表**已验证整夜稳定在线、每次重启自动恢复或断线消息补收。端口正常也不等于整个 OneBot/Hook 链路始终正常。

## 🧭 v0.2 探索日记集成说明

本版本复用手机 Ubuntu **已有**的探索日记服务，不把日记服务器或个人档案打包进 APK，也不自动安装第三方 Skill。

- Ubuntu 内预期目录：`/opt/whale/QQ-agent-K0nd1us/0.4/whale-diary`。
- 至少存在 `server.py`、`start.sh`、`url.sh`；推荐使用 **whale-explorer-diary v0.1.1**。
- 点击「打开／启动探索日记」后，控制层先检查 `http://127.0.0.1:3222/health`；若未启动再调用现有 `start.sh`，只有本机健康检查通过才读取并打开带密钥的日记链接。
- 日记继续由原项目在本机 `127.0.0.1:3222` 提供。App 不会在网络中公开端口，不读取或修改探索 JSON，也不会把带密钥的 URL 打印进操作日志。
- 「探索日记随大肥鱼启动」默认为**关闭**。开启后会记录一个 KernelSU Root 标志位；下次启动 QQ 主服务时尝试启动日记。守护进程只负责 QQ 主服务健康检查，不会因为日记离线就重启整个 QQ。
- 「设备内存」是 **Android 宿主机总 RAM 与可用 RAM**，不是 QQ Agent 的单进程内存；根文件系统存储使用量也不等于 QQ 数据大小。

**关于重启：** 更新 APK 不需要立刻重启手机或 Ubuntu；App 打开时会重新安装 Root 控制脚本，但不会启动/重启 QQ、SnowLuma。开机联动效果须等用户之后自主重启手机才能验收。QQ Agent 的实际工具状态仍请以其 `技能` 页和会话工具调用为准。

**安全说明：** 日记链接包含片段形式访问密钥，只在用户点击时交给 Android 浏览器。浏览器的历史记录和截图仍可能暴露密钥；不要分享完整网址。与本机服务交互所用的 `su` 权限非常高，请在安装 APK 前自行审阅脚本。

## 🛠️ 环境要求

- 已 Root 的 ARM64 安卓设备（此控制台按 **KernelSU** 部署编写）。
- KernelSU 内置 BusyBox 可在 `/data/adb/ksu/bin/busybox` 运行。
- 已部署的 Ubuntu ARM64 chroot：`/data/local/chroot/ubuntu`。
- Ubuntu 内已有可用的 `/root/start-whale.sh` 与 `/root/stop-whale.sh`。
- Ubuntu 中已安装并配置 Linux QQ、SnowLuma、QQ Agent。

> **注意**：本仓库提供控制台源码和教程，并非开箱即用的一体化安装包。部署顺序、路径说明和数据备份事项请以 [Root 完整教程](docs/安卓Root部署大肥鱼QQAgent_完整教程.md) 为准。

## 📦 构建 APK

本项目使用 **JDK 17、Gradle 8.9、Android Gradle Plugin 8.7.3、Android SDK 35**。已提供 GitHub Actions 自动构建配置。

1. 打开仓库的 **[Actions](https://github.com/silent07137/whale_android_controller/actions)**。
2. 选择 **Build 大肥鱼控制台 APK**，可手动运行工作流；推送到 `main` 后也会触发。
3. 构建成功后，在对应运行页面的 **Artifacts** 下载 `WhaleController-debug-apk`。
4. 解压获得 `app-debug.apk`，安装到自己的安卓手机，并在 **KernelSU → 超级用户** 中核实后授予 Root 权限。
5. 首先点击「刷新运行状态」，再测试启动、停止及真实 QQ 消息。**不要在首次测试时就打开开机自启。**

Debug APK 的签名可能随构建环境变化。遇到签名不一致时需要处理旧应用的安装问题，但**不要删除 Ubuntu、Termux 或数据备份**。

## 🔐 安全与运行边界

- App 通过 `su -c` 调用 Root 脚本，拥有较高权限；安装前务必检查 [Root 控制脚本](app/src/main/assets/controller.sh)。
- 当前脚本使用 **KernelSU 自带 BusyBox**（`/data/adb/ksu/bin/busybox`），不需要复制 Termux 私有目录中的 BusyBox 启动文件。
- 旧的 Termux:Widget 守护器与本 App 的守护器不要同时运行，避免相互拉起服务。
- 后台隐藏**不等于**绝对保活。部分系统可能停止后台进程；开机启动、QQ 登录状态、消息补收均需独立测试。
- 不要提交 `data/config.json`、QQ 凭据、个人聊天日志、OneBot Token、API Key、加密备份密码或未脱敏的运行日志。
- 所有第三方软件和服务遵循各自的许可与服务条款。

## 🗂️ 仓库结构

```text
app/                              Android 控制台原生源码、Root 管理脚本
.github/workflows/android-apk.yml  GitHub Actions APK 构建
docs/                             Root 部署教程与 Shizuku 可行性研究
docs/LICENSE.md                    文档的 CC BY-NC-SA 4.0 使用说明
LICENSE                            控制台源码的 GPLv3 正式许可证文本
README.md                          项目说明
```

仓库根目录保留的 `whale_android_controller_source_v0.1.zip` 是**早期历史源码包**，如需最新版本请以当前 `app/` 源码和 Actions 构建产物为准。

## ⚖️ 许可证与版权

本仓库**分开授权代码与教程**：

- **控制台及原创程序源码**：**[GNU GPL-3.0-only](LICENSE)**。这是 OSI 承认的开源软件许可证，允许商业使用，但传播和修改必须满足 GPLv3 的相应义务。**不能据此主张“代码禁止商用”**。
- **`docs/` 下两篇原创教程文字与编排**：**[CC BY-NC-SA 4.0](docs/LICENSE.md)**。要求署名、非商业使用、相同方式共享；商业用途请另行取得作者许可。它**不是开源软件许可证**，不用于限制程序源码。
- **第三方组件、商标和引用资料**：由各自权利人及其原有许可证管理，以上授权均不覆盖第三方权利。

**© 2026 silent07137**。转载教程请注明作者和原始仓库链接，并保留原有版权声明、显式署名及溯源注释。

<!-- provenance-id: S07137-WHALE-REPO-README-20261025; author=silent07137; applies-to=README-only -->
