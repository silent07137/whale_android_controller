# Shizuku（ADB 授权）部署 QQ Agent：可行性分析与实验教程

> **研究结论（请先读）**：**仅靠 Shizuku 的 ADB 授权，不能等价复现已 Root 的 KernelSU + 真正 chroot + Linux QQ + SnowLuma + QQ Agent + Root 守护部署。** 但在**无 Root** 安卓设备上，改用 **Termux + PRoot Ubuntu** 可以搭建大部分用户态服务，并且 SnowLuma 官方已有对应的**实验性** Android 路线。**能否将 Linux QQ 成功 Hook 并完成 QQ 消息收发，尚未验证，不能宣称完整部署成功。**
>
> **评估日期**：2026-10-25　　**文档性质**：技术可行性论证 + 分阶段实验指导（不是已完成的无 Root 实测报告）
>
> **对照案例**：已在 ARM64 安卓手机上实际跑通的 **KernelSU Root + Ubuntu 24.04 ARM64 chroot + Linux QQ + SnowLuma v2.1.1 + K0nd1us/QQ-agent 0.4 + 独立控制台 APK**。该案例已验证 QQ 实际消息回复、控制台隐藏最近任务及约六分钟后台运行；**尚未完成无 Root 实验、整夜保活和重启后可靠自恢复验证**。
>
> **不包含**：模型提示词、人设、私人 Token、QQ 登录数据、API Key。以下所有命令均供自己的设备测试，执行前核对来源。

> **原创整理与署名**：© 2026 **silent07137**。本可行性报告及实验教程的文字整理、对照分析和教学结构由作者编写。仅供个人学习与非商业研究；未经书面授权不得商业售卖、打包分发或用作收费培训教材。转载需保留署名及来源，第三方项目权利与原许可不变。

> **文档授权**：© 2026 silent07137。本教程原创文字部分使用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 授权，转载请署名并保留溯源信息；商业使用需另行获得作者许可。第三方软件、商标和所引用材料不在此授权范围内。

<!-- provenance-id: S07137-WHALE-SHIZUKU-20261025-ED2; author=silent07137; format=Markdown -->

## 一、可行性声明

### 1.1 必须区分的三种“可行”

| 目标 | 结论 | 说明 |
| --- | --- | --- |
| 在无 Root 手机上启动 Shizuku（ADB 模式） | **可行，官方支持** | Android 11 及以上可采用无线调试；重启后通常需要重新启动 Shizuku。 |
| 在无 Root 手机上搭建 Ubuntu 用户态、图形环境、Node.js 和 QQ Agent | **原则可行，条件依赖** | 可由 Termux + PRoot 实现，不需要 Shizuku 提供 Root。可运行 Node.js、HTTP/WS 服务及图形用户态程序。 |
| 在无 Root 手机上运行 Linux QQ + SnowLuma，实现真正的 OneBot 收发 | **实验性可行，未保证成功** | 关键瓶颈为 PRoot 与 SnowLuma 的 `ptrace` 注入机制、Android 内核及 SELinux 限制。需真机完成 Hook/消息测试。 |
| 仅将原 KernelSU 控制台的 `su` 换成 `rish`，直接运行原方案 | **不可行** | ADB shell（通常 UID 2000）不具备 Root 的真实 `chroot`/`mount` 权限，也无法访问 Termux 私有文件。 |
| 在仅有 Shizuku ADB 授权的情况下保留原 Root 开机脚本和内核级守护 | **不可行** | `/data/adb/boot-completed.d` 等 Root 启动通道不能由普通 ADB 模式取代。 |
| 无 Root、手机本机运行 QQ Agent，并连接外部已可用的 OneBot 端 | **可行性较高** | QQ Agent 本身主要是 Node.js 服务；但如协议端在外部设备，此时就不再满足“QQ 全链路完全本机运行”。 |

**一句话判定：**“Shizuku ADB 授权实现此前 Root 方案的原样复制”是**不可行**；“无 Root 安卓使用 PRoot 探索本机完整 QQ 机器人”是**有条件、实验性可行**；“全链路稳定常驻、无人工干预重启恢复”在此条件下**不能保证**。

### 1.2 置信与验证状态

- **已被项目文档明确支持**：Shizuku ADB 模式的权限边界；PRoot 无 Root 的 Ubuntu 用户态；SnowLuma Android/PRoot 实验路径；QQ Agent 独立连接 OneBot 的运行方式。
- **从技术实现推断**：无 Root PRoot 内的 `setcap` 不会凭空赋予 Android 宿主内核真实的 `CAP_SYS_PTRACE`；不能期待 ADB 授权让所有 QQ 注入操作成功。
- **尚未验证**：目标手机的 PRoot 是否能稳定运行 Linux QQ、能否完整注入 SnowLuma、锁屏后接收 QQ 事件的长期稳定性、无 Root 的独立 APK 控制器。

## 二、为何 Shizuku 不等于 Root

### 2.1 权限模型

```text
已 Root 的既有成功方案
    KernelSU / su → UID 0（Root）
       ├─ mount --bind、真实 chroot
       ├─ /data/local/chroot/ubuntu
       ├─ /data/adb/ksu/bin/busybox
       └─ Root 后台脚本与 boot-completed.d

无 Root 的拟议方案
    Shizuku（通过 ADB 启动） → UID 2000（shell）
       ├─ 调用其权限范围内的安卓系统服务 / ADB shell 操作
       └─ 不能因此取得 UID 0、真实 mount、真实 chroot

    Termux（普通应用 UID）
       └─ PRoot（ptrace 用户态路径转换；非真正 chroot）
           ├─ Ubuntu ARM64 用户态
           ├─ Xvfb / VNC / Linux QQ（待验证）
           ├─ SnowLuma（Hook 待验证）
           └─ QQ Agent 0.4（条件可运行）
```

Shizuku 官方将 ADB 模式的权限与 Root 模式明确区分。通过 Shizuku 授权，只能使用 Shizuku 进程*实际上拥有*的权限；不会把手机上的其他 App 自动提升为 Root，也不会让远程 `rish` 进程拥有 Termux 应用的私有目录访问权。[资料 S1、S2、S3]

### 2.2 `rish` 能做什么、不能做什么

`rish` 是 Shizuku 提供的远程 shell 调用方式。例如：

```sh
rish -c 'id -u'
```

- 若结果是 **`2000`**，说明是 ADB/shell 权限，不是 Root。
- 若结果是 **`0`**，说明所用 Shizuku 后端有 Root 权限，**不属于本次“无 Root、仅 ADB 授权”研究条件**。
- `rish` 适用于部分 ADB/shell 可做的系统管理操作，但不适合直接替换原控制台的 `su -c`，也不能用来读取 `/data/data/com.termux/files/home` 中其他 UID 的文件。

**不建议试图靠关闭 SELinux、篡改系统分区、漏洞提权来弥补这个差距。** 这会改变研究前提，并带来较高安全风险。

## 三、与我们成功的 KernelSU 方案逐项对照

| 组件或能力 | Root / KernelSU 已完成案例 | Shizuku（ADB）+ 无 Root 替代方案 | 判定 |
| --- | --- | --- | --- |
| Root 授权与真实 Linux 权限 | KernelSU `su` | Shizuku ADB shell 仅 UID 2000 | **不能替代** |
| Ubuntu 24.04 | `/data/local/chroot/ubuntu` 真 chroot | Termux `proot-distro` 中的 Ubuntu 24.04 | **能替换用户态，非等价** |
| `/dev`、`/proc`、`/sys` 真实 bind mount | BusyBox `mount --bind` | PRoot 用户态虚拟路径绑定 | **仅部分模拟** |
| Linux QQ ARM64 | 已实测可运行、可登录 | PRoot 内按 Linux 手动流程启动 | **待真机验证** |
| Xvfb + Fluxbox | 已实测 | Ubuntu 用户态可尝试安装 | **原则可行** |
| x11vnc / websockify / noVNC | 已实测 5900/6081 | PRoot 内尝试运行并监听 127.0.0.1 | **原则可行** |
| SnowLuma 服务进程、5099 WebUI | 已实测 | 选择 Linux ARM64 程序，可尝试启动 Node | **条件可行** |
| SnowLuma 对 QQ 的 `ptrace` Hook | Root 真 chroot 下已实测 | PRoot 的 ptrace 与 Hook 注入冲突风险 | **最大不确定项** |
| OneBot WS 3001 / HTTP 3000 | 已实测连通 | 仅在 Hook 与适配器成功后有效 | **依赖上一项** |
| K0nd1us QQ Agent 0.4 / 3210 | 已实测 | 在 Ubuntu PRoot 内用 Node.js 启动 | **可行性较高** |
| 真正 QQ 消息接收与回复 | 已实测 | 必须经过 Hook + OneBot 全链路验收 | **尚不可声明成功** |
| 独立 Root 控制台 APK | 已实测点击启动，不打开 Termux | 需重做通信和服务管理架构 | **现有 APK 不能直接复用** |
| 后台隐藏最近任务 | 控制台已实测 | 自己的 Android Activity 可以隐藏自己的任务卡片 | **UI 层可行，与保活无关** |
| KernelSU 脚本开机自启 | Root 引擎支持；案例尚未验证重启 | ADB Shizuku 不支持原样使用 Root 脚本 | **不能替代** |
| 锁屏长时间保活 | 仅有短时实测 | Termux 电池例外、唤醒锁等缓解措施 | **不保证稳定** |


> *技术报告署名：© 2026 silent07137 · 允许个人非商业学习与验证 · 商业使用须事先授权。*

<!-- doc-origin: s07137/shizuku/ptrace/b23; attribution-required -->

## 四、最关键的障碍：SnowLuma 的 `ptrace` 注入

SnowLuma 官方的 Linux 手动部署文档说明，原生 Hook 会**通过 `ptrace` 注入 QQ 进程**；普通 Linux 上通常通过 `CAP_SYS_PTRACE` 或符合内核策略的跟踪权限解决。[资料 S4]

PRoot 同样依赖 `ptrace` 来拦截来宾程序的系统调用。两者发生嵌套、进程跟踪关系冲突、内核/SELinux 拦截时，可能出现：

1. Ubuntu 与 Node.js 能运行，SnowLuma WebUI 5099 也能打开。
2. Linux QQ 能显示登录页面甚至登录成功。
3. **SnowLuma Hook 却无法注入 QQ**，因此没有正常的 OneBot 消息事件。
4. QQ Agent 的 3210 管理界面虽可访问，却无法回复真正的 QQ 消息。

SnowLuma **官方手机部署页面**明确将 **Termux + PRoot** 列为实验路线，且明确把 `ptrace` 注入列为最大不确定点。[资料 S5]

### 为什么不能照抄“`setcap cap_sys_ptrace=ep`”？

PRoot 内看到的 `root` 经常是模拟 UID，不等于 Android 宿主的真实 Root。即使某个 `setcap` 操作表面成功，也不能据此宣称已经获得宿主内核的真实 `CAP_SYS_PTRACE`。**Shizuku ADB 模式无法授予这项真正的 Linux capability。** 不要将这项测试当成可靠解法。

### 建议的停止条件

**若 Linux QQ 已正常运行，SnowLuma 仍报告 Hook 注入失败，且原生错误涉及 ptrace/权限/PRoot 追踪冲突，应暂停本机完整方案验证。** 不建议继续为追求兼容性而关闭 SELinux 或修改系统安全策略。可选择 Root chroot 或另一台设备提供协议端。

## 五、推荐的三种路线

### 路线 A：无 Root + Termux PRoot + 本机全链路（本研究主线）

```text
Shizuku（可选：安卓管理权限）
Termux（必需：承载 Linux 进程）
└─ PRoot Ubuntu 24.04 ARM64
   ├─ Xvfb + Fluxbox + VNC/noVNC
   ├─ Linux QQ（实验）
   ├─ SnowLuma（Hook 实验）
   └─ QQ Agent 0.4
```

**可行性声明：实验性。** 本方案真正承担 Linux 部署的是 Termux/PRoot，Shizuku 并不是使 Ubuntu 成功运行的核心条件；可以先完全不装 Shizuku，验证 PRoot 后再考虑控制面集成。

### 路线 B：无 Root + Termux QQ Agent + 远程 OneBot（备选）

```text
安卓 Termux：QQ Agent 0.4（Node.js）
               ↑ WebSocket / HTTP（经过安全认证）
另一台 Linux/服务器：QQ + SnowLuma / 可用 OneBot 协议端
```

**可行性声明：条件可行，工程难度明显较低。** 最难的 `ptrace` 注入在正常 Linux 环境解决；但不能再称为“全套 QQ 都部署在手机本机”。同时要注意跨设备访问、Token 与网络安全。

### 路线 C：保留已成功的 Root + KernelSU 真 chroot

**可行性声明：该设备已完成主要功能实测，当前最可靠。** 如果手机本来就有 Root，仅为了改用 Shizuku 而把真 chroot 换成 PRoot，通常是增加复杂度、降低注入成功率，而不是升级。

## 六、无 Root 实验：准备与 Shizuku ADB 授权

> **实验环境**：ARM64 安卓手机；Android 11 及以上可用无线调试；无 Root；具备网络访问；建议 8 GB 起，12 GB 或更多会更从容，需有足够存储空间。以下从零开始，不覆盖现有 Root Ubuntu。 

### 6.1 安装 Shizuku

只从官方渠道获取：

- Shizuku 官网：https://shizuku.rikka.app/
- 官方安装/启动指引：https://shizuku.rikka.app/zh-hans/guide/setup/

步骤：打开开发者选项与无线调试 → 进入 Shizuku 选择“通过无线调试启动” → 首次使用时进行配对码配对 → 启动服务 → 确认界面显示运行中。

Shizuku 官方说明，**Android 11 及以上无线调试方式无需电脑常驻**；但**重启后通常要重新启动 Shizuku**，部分厂商的后台限制会影响连接。[资料 S1]

如需验证权限，在 Shizuku 官方说明下获取 `rish` 文件，通过支持的终端运行：

```sh
rish -c 'id -u'
```

预期无 Root 的 ADB 模式为 `2000`。`rish` 的具体安装/环境变量配置应按对应版本的官方说明执行，不要从陌生来源复制替换文件。[资料 S3]

**说明：到这一步只是 Shizuku 运行成功，并不代表任何 QQ 组件已经部署。**

### 6.2 安装普通 Termux

安装来源（择一）：

- https://f-droid.org/packages/com.termux/
- https://github.com/termux/termux-app/releases

不要将不同签名来源的 Termux 与插件混装。如果设备已有正常使用的 Termux，无需卸载它。

在 **普通 Termux** 运行：

```bash
pkg update && pkg upgrade -y
pkg install -y proot-distro git curl wget tar unzip procps
termux-setup-storage
uname -m
id -u
```

- 架构应为 `aarch64`。
- Termux 自己的 UID **不应是 `0`**；无 Root 条件下 UID 是 Android 分配的应用 UID。
- `termux-setup-storage` 需要安卓存储权限，仅用于文件访问。


> *技术报告署名：© 2026 silent07137 · 允许个人非商业学习与验证 · 商业使用须事先授权。*

<!-- doc-origin: s07137/shizuku/proot/b47; authored-teaching-material -->

## 七、无 Root 实验：Ubuntu 用户态与基础依赖

### 7.1 安装 Ubuntu PRoot

在 **普通 Termux** 执行：

```bash
proot-distro install ubuntu:24.04
proot-distro login ubuntu
```

这是 PRoot-Distro 当前文档中的 Ubuntu 24.04 示例。安装版本/容器名由安装成功后的输出为准；若仓库版本发生变化，以 `proot-distro --help`、`proot-distro list` 及官方 README 为准。[资料 S6]

进入 **PRoot Ubuntu** 后检查：

```bash
cat /etc/os-release
uname -m
id -u
```

这里的 `id -u` **可能显示 0，但只是 PRoot 对容器身份的模拟，不表示真实 Root**。不要据此运行 `mount --bind`、真实 `chroot` 或 KernelSU 脚本。

### 7.2 安装用户态依赖

在 **PRoot Ubuntu** 中：

```bash
apt update
apt install -y \
  ca-certificates curl wget git tar unzip \
  procps psmisc iproute2 \
  xvfb fluxbox x11vnc novnc websockify dbus-x11 \
  fontconfig fonts-noto-cjk \
  libgbm1 libnss3 libasound2t64 libgtk-3-0 \
  libxshmfence1 libxdamage1 libdrm2 libxkbcommon0
```

PRoot 的程序包管理与大量纯用户态软件通常可以使用，但运行 Linux Electron/QQ 等图形程序的兼容性需要继续测试。若某些依赖包名发生变更，应以当前 Ubuntu 软件源为准。

### 7.3 安装 Node.js

SnowLuma 手机指南采用 Node.js 24 LTS，QQ Agent 0.4 要求 Node.js 20 或更新。可参照 NodeSource 的当前说明配置 Node 24；下面展示先下载安装脚本以便检查的方式：

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/setup_node24.sh
# 先查看并核对脚本来源与内容，再自行执行：
# bash /tmp/setup_node24.sh
# apt install -y nodejs
node -v
npm -v
```

此时若尚未安装 Node，最后两行报 `command not found` 属预期，请完成官方 Node.js 安装流程后重试。不要为了省事把来源不明的安装脚本直接管道送入 Shell。

## 八、无 Root 实验：虚拟桌面与 Linux QQ

### 8.1 启动 Xvfb / Fluxbox

在 **PRoot Ubuntu** 中：

```bash
mkdir -p /root/.vnc
x11vnc -storepasswd

Xvfb :1 -screen 0 1280x720x24 -nolisten tcp \
  > /tmp/xvfb.log 2>&1 &
export DISPLAY=:1
fluxbox > /tmp/fluxbox.log 2>&1 &

x11vnc -display :1 -localhost -rfbport 5900 \
  -rfbauth /root/.vnc/passwd -forever -shared \
  > /tmp/x11vnc.log 2>&1 &

websockify --web=/usr/share/novnc \
  127.0.0.1:6081 127.0.0.1:5900 \
  > /tmp/websockify.log 2>&1 &
```

手机浏览器访问：`http://127.0.0.1:6081/vnc.html`。

**验收关卡 G1**：能打开页面并看到 Linux 图形桌面。失败时优先检查 `/tmp/xvfb.log`、`/tmp/x11vnc.log` 和 `/tmp/websockify.log`。这部分不需要 Shizuku 提供 Root。

### 8.2 安装 Linux QQ ARM64

官方来源：https://im.qq.com/index/#/linux

> **下载入口说明**：此链接是 QQ 官方 Linux 下载网页，不是 `.deb` 直链。请通过安卓浏览器进入 Linux 下载区，选择 **ARM64 / aarch64 的 Debian `.deb` 包**，不要选择 AMD64、RPM 或 AppImage，也不要将官网页面保存为 `.deb`。

用手机浏览器下载 **Linux ARM64 `.deb`**（不要下载 Android APK 或 Linux AMD64 包）。可以使用 PRoot 的路径绑定把下载文件映射进 Ubuntu，例如在**普通 Termux**：

```bash
proot-distro login --bind "$HOME/storage/downloads:/mnt/downloads" ubuntu
```

然后在 **PRoot Ubuntu** 中把真实文件名替换为自己的下载包：

```bash
ls -lh /mnt/downloads/
# 替换为你实际下载的文件名，并核对 Debian 架构
dpkg-deb -f /mnt/downloads/实际QQ文件名.deb Architecture
dpkg --print-architecture
# 两者应为 arm64，确认后再安装
apt install -y /mnt/downloads/实际QQ文件名.deb
ls -l /opt/QQ/qq
```

> 以上 `--bind` 为 PRoot-Distro 支持的**用户态路径映射**，并非 `mount --bind`。如果安卓限制了下载目录访问，先用 Termux 把文件复制到自己可访问的目录，再绑定；不要使用 ADB shell 强行读取 Termux 的私有文件。

启动 Linux QQ（实验性）：

```bash
export DISPLAY=:1
/opt/QQ/qq --no-sandbox --disable-gpu \
  --disable-dev-shm-usage \
  > /tmp/linuxqq.log 2>&1 &
```

使用 noVNC 查看能否弹出 QQ 窗口并登录。`--no-sandbox` 会降低 Chromium/Electron 的隔离保护；这里仅作为兼容测试参数，若有可正常运行的沙箱配置应优先使用。

**验收关卡 G2**：QQ 进程存在、图形窗口可见、用户完成登录。如果 QQ 无法启动，则不要继续宣称本机全链路可行。

## 九、无 Root 实验：SnowLuma 与 OneBot

在 **PRoot Ubuntu** 中，从 SnowLuma 官方 Releases 下载**匹配 ARM64 的 Linux 发行包**，以解包后能找到 `index.mjs`、相应 `native/` 模块为前提。具体包名与版本以发布页面为准：

https://github.com/SnowLuma/SnowLuma/releases

推荐参考官方“手机部署（实验性）”与“Linux 手动部署”的版本说明，不要把当前 Root 实测的绝对路径直接照搬到 PRoot 中。

假设已将程序放入 `/opt/whale/snowluma`，在 **PRoot Ubuntu** 中尝试：

```bash
cd /opt/whale/snowluma
export DISPLAY=:1
SNOWLUMA_HOOK_AUTOLOAD=1 node ./index.mjs \
  > /tmp/snowluma.log 2>&1 &
```

按官方顺序，优先在 Xvfb 准备好后启动 SnowLuma，再拉起 QQ。若 QQ 已经启动，实验中可先正常退出 QQ，再尝试 SnowLuma → QQ 的顺序。

查看：

```bash
tail -n 100 /tmp/snowluma.log
```

WebUI：`http://127.0.0.1:5099`。登录初始化方式以其当前版本指引为准。

**重要：仅有 5099 可访问不算通过。** 须在 SnowLuma 里确认 QQ Hook 真正加载、OneBot 实例建立，并用独立客户端或日志确认 `ws://127.0.0.1:3001` 可以持续收到 QQ 消息事件。OneBot HTTP API 常使用 `http://127.0.0.1:3000`，但配置、账号实例与 Token 必须以当前 SnowLuma 实际值为准。

**验收关卡 G3（决定性）**：Linux QQ 已登录 + SnowLuma Hook 成功 + 发送测试消息可看到真实 OneBot 事件。**如果 G3 不通过，直接判定本机完整 QQ Agent 方案当前不可用；不要被 WebUI 页面“在线”的假象误导。**

## 十、无 Root 实验：QQ Agent 0.4

只有在 **G3 已经通过** 后，才值得继续做完整链路集成。在 **PRoot Ubuntu** 执行：

```bash
mkdir -p /opt/whale
cd /opt/whale
git clone https://github.com/K0nd1us/QQ-agent.git QQ-agent-K0nd1us
cd /opt/whale/QQ-agent-K0nd1us/0.4
npm install
npm run server
```

浏览器打开 `http://127.0.0.1:3210`，在控制台中按实际 SnowLuma 配置填入 OneBot 的 WebSocket/HTTP 地址和令牌。

**验收关卡 G4**：另一 QQ 账号发消息，QQ Agent **真实收到并回复**。仅浏览器打开 3210 不算通过；也不要把模型 API 调用成功等同于 QQ Hook 正常。QQ Agent 官方将 OneBot 作为外部协议端，因此 QQ Agent 本身与 SnowLuma/QQ Hook 是可以分开测试的。[资料 S7]


> *技术报告署名：© 2026 silent07137 · 允许个人非商业学习与验证 · 商业使用须事先授权。*

<!-- doc-origin: s07137/shizuku/background/b65; redistribution-not-for-sale -->

## 十一、独立控制 App、后台隐藏和保活能否迁移？

### 11.1 现有 KernelSU APK 为什么不能直接用

现有控制台在 Root shell 中调用 `/data/adb/ksu/bin/busybox`、真实 chroot、挂载和 KernelSU 开机脚本。Shizuku ADB 的 shell 不具备等价权限，**简单把代码中的 `su` 替换成 `rish` 不会成功**。

无 Root 控制台应重新设计为：

1. 原生 Android Activity 负责界面、显示运行状态和“最近任务隐藏”（仅隐藏自己的卡片）。
2. **实际 Linux 生命周期由 Termux 所属 UID 管理**，例如通过明确授权的 IPC、受保护的本机回环接口或 Termux 插件机制调用 PRoot 管理脚本。
3. Shizuku（如果使用）仅执行权限范围内的 Android 系统管理操作，不替代 Linux 运行时，也不要求读取 Termux 私有目录。
4. 本机控制 API 必须验证调用者，不能把任意 Shell 命令执行接口直接暴露给局域网或其他 App。

**控制台 UI 可以开发，但“无 Root + 启动服务不弹 Termux 最近任务卡片 + 长期守护”的完整组合需要单独开发与实测**，目前不属于已交付的 KernelSU APK 功能范围。

### 11.2 后台保活的现实限制

Android 12 及以上对后台子进程和高 CPU 负载有额外限制；Termux 项目也提醒进程可能被系统终止。建议：

- 允许 Termux 后台运行、设置电池使用无限制，按系统提供的正规方式锁定后台任务。
- 使用 `termux-wake-lock`（在普通 Termux 运行；该操作会增加耗电），但**唤醒锁不是永不被杀的保证**。
- 使用 Termux 自身支持的会话/后台任务管理，避免多个独立守护互相拉起。
- 采用分阶段实测：30 分钟 → 2 小时 → 8 小时，分别检查 QQ 实际回复与日志。
- 安卓前台服务及通知的要求仍然适用；“最近任务没有卡片”不能推导出“不会被系统杀掉”。

### 11.3 无 Root 开机自启

Shizuku 官方指出，**ADB/无线调试启动方式在设备重启后需再次启动服务**。因此不能承诺一个依赖 Shizuku 常驻连接的无 Root 控制器在重启后自动恢复一切。[资料 S1]

Termux:Boot 一类方式可以作为**无 Root 的可选开机触发机制**进行探索，但能否自动启动多个 PRoot/Electron/QQ 进程取决于安卓版本、省电策略、首次解锁状态与系统限制。它也不是 KernelSU `boot-completed.d` 的等价替换。本研究尚未实测。

## 十二、实验记录表：何时才能把“实验性可行”改成“已验证可行”？

| 关卡 | 需要保留的证据 | 通过标准 | 未通过时结论 |
| --- | --- | --- | --- |
| G0 Shizuku | Shizuku 管理界面、`rish -c 'id -u'` | ADB 模式能正常工作，UID 2000 | Shizuku 控制功能不可用；不妨碍独立试验 PRoot |
| G1 PRoot/图形环境 | Ubuntu 版本、Xvfb/noVNC 日志 | 浏览器可见 Linux 图形桌面 | 先解决用户态图形/PRoot 兼容性 |
| G2 Linux QQ | `/tmp/linuxqq.log`、QQ 登录界面 | QQ ARM64 真正登录 | 本机完整 QQ 链路暂不可用 |
| **G3 SnowLuma Hook** | 原生日志、OneBot 事件 | **能真实收到 QQ 消息事件** | **关键阻塞；不能宣称完整部署可行** |
| G4 QQ Agent | QQ Agent 日志及双向消息 | **另一个 QQ 发消息后收到自动回复** | 检查 OneBot、Token、模型接口 |
| G5 锁屏保活 | 30 分钟、2 小时、8 小时测试记录 | 锁屏后消息持续往返 | 仅能作为不稳定实验环境使用 |
| G6 重启恢复 | 冷启动及首次解锁测试 | 不依赖人工修复，能恢复 QQ 回复 | 不能声明无人值守开机自启 |

**只有 G1～G4 全部通过，才可以说“这台具体机型上的无 Root、本机 QQ Agent 全链路已部署成功”。** 如果还要宣称“可长期稳定部署”，至少另需 G5、G6 的长期重复测试。不同 ROM、内核和 Android 版本不自动继承成功结论。

## 十三、常见误判与故障排查

| 表现 | 不能直接得出的结论 | 优先检查 |
| --- | --- | --- |
| Shizuku 显示“运行中” | 不能证明已获得 Root | `rish -c 'id -u'`、官方 ADB 权限范围 |
| PRoot 内 `id -u` 显示 0 | 不能证明有真实 `CAP_SYS_PTRACE` | Android 宿主身份、PRoot 的用户态模拟原理 |
| Ubuntu 能 `apt install` | 不能证明 QQ 图形程序和 Hook 一定能运行 | Electron 库依赖、Xvfb、PRoot ptrace |
| 6081 noVNC 正常 | 不能证明 Linux QQ 已登录 | `linuxqq.log`、QQ 窗口与登录态 |
| 5099 SnowLuma WebUI 正常 | 不能证明 QQ Hook 已注入 | SnowLuma native/ptrace 日志、OneBot 事件 |
| 3210 QQ Agent 面板正常 | 不能证明 QQ 可以自动回复 | WS/HTTP Token、G3、实际发消息测试 |
| 关掉控制台后还能运行数分钟 | 不能证明整夜保活 | 电池限制、后台子进程回收、长时记录 |
| 最近任务卡片消失 | 不能证明进程仍存活 | 实际服务进程与消息回执 |
| 手机重启后 Shizuku 不运行 | 不是 QQ 组件数据损坏 | 官方要求重新启动 ADB 模式 Shizuku |

## 十四、安全、法律与维护建议

1. 仅使用自己有权使用的 QQ 账号与授权的模型服务，遵守软件与平台的使用规则；第三方 Hook 可能因 QQ 更新失效，也可能触发平台风控。
2. 将 QQ、SnowLuma、QQ Agent 的账号凭据、VNC 密码、OneBot Token、API Key 保存在本地私有路径，不提交到 GitHub。配置备份应加密，并验证是否可解密恢复。
3. 只监听 `127.0.0.1`，不要将 3000、3001、3210、5099、5900、6081 等管理端口无鉴权暴露到公网；外部访问需要加密与明确鉴权。
4. 不要为了获得 Hook 权限而关闭 SELinux 或尝试提权漏洞。Shizuku ADB 权限本来就不是 Root，这是设计边界。
5. 对照 Root 案例时，保留已验证的 Root 部署及备份，**不要把实验用 PRoot 直接覆盖原 Ubuntu chroot 数据**。
6. 插件、Skills 等可执行扩展要审查来源；“无 Root”不会自动使不可信代码安全。


> *技术报告署名：© 2026 silent07137 · 允许个人非商业学习与验证 · 商业使用须事先授权。*

<!-- doc-origin: s07137/shizuku/verdict/b88; preserve-attribution -->

## 十五、最终可行性判定与推荐

### 15.1 对“能否仅用 Shizuku ADB 完成此前部署”的回答

**不能原样完成。** 权限层面没有真实 Root；架构上必须把真 chroot 改成 PRoot，放弃 KernelSU Root 脚本，重写控制器。关键 SnowLuma Hook 在 PRoot 下又存在尚未解决的 `ptrace` 不确定性。

### 15.2 对“无 Root 能否实现类似功能”的回答

**可以尝试，且官方已有实验路线，但目前不能保证完整收发。** 建议按 G1 → G2 → **G3** → G4 的顺序验证，尤其先证明 SnowLuma Hook 确实在这台设备上工作，再投入后台控制台与长时间保活开发。

### 15.3 针对已有成功 KernelSU 部署的建议

- **主力、需要可靠 QQ 消息的场景**：继续使用 KernelSU 真 chroot 方案；现有成功部署的经验仍有价值。
- **希望研究完全无 Root**：另建 Termux PRoot 环境做 G1～G3 小规模验证，不替换现有环境。
- **最重视无 Root 稳定性而非完全本机**：将 OneBot 协议端放在支持 `ptrace` 的独立 Linux 环境，手机只运行 QQ Agent 控制/业务服务。

### 15.4 最终声明

> **Shizuku ADB-only：无法等价部署已验证的 KernelSU Root 方案。**  
> **Termux + PRoot + SnowLuma + QQ Agent：官方承认是 Android 的实验性途径，核心 Hook 必须实测，当前结论为“部分可行，完整性待验证”。**  
> **本文没有完成无 Root 真机实验，因此不得据此宣称“全链路已实测可行”“长期稳定保活”或“能够自动恢复所有消息”。**

---

## 参考资料（官方/项目一手文档）

- **Linux QQ 官方 Linux 下载页**：https://im.qq.com/index/#/linux（在页面内选择 ARM64 `.deb`；仅用于 G2 实验）。

- **S1**：Shizuku 官方用户手册（ADB 无线调试启动、重启限制与厂商兼容性）：https://shizuku.rikka.app/zh-hans/guide/setup/
- **S2**：Shizuku-API README（UID 0 / UID 2000、权限边界与 UserService）：https://github.com/RikkaApps/Shizuku-API/blob/master/README.md
- **S3**：Shizuku-API `rish` 文档（ADB shell、环境隔离、Termux 路径不可访问）：https://github.com/RikkaApps/Shizuku-API/blob/master/rish/README.md
- **S4**：SnowLuma Linux 手动部署（native Hook、`ptrace` 与 `CAP_SYS_PTRACE`）：https://snowluma.github.io/zh/docs/guide/deploy/linux-manual
- **S5**：SnowLuma 手机部署（Android，实验性；PRoot 与 ptrace 冲突风险）：https://snowluma.github.io/zh/docs/guide/deploy/mobile
- **S6**：Termux PRoot-Distro 官方 README（无 Root Linux 用户态、ptrace、限制及 `--bind`）：https://github.com/termux/proot-distro/blob/master/README.md
- **S7**：K0nd1us QQ Agent 0.4 README（Node.js、OneBot 与无桌面 `npm run server`）：https://github.com/K0nd1us/QQ-agent/blob/main/0.4/README.md
- **S8**：Termux 官方 README（Android 12+ 后台进程回收风险）：https://github.com/termux/termux-app/blob/master/README.md
- **S9**：KernelSU 模块文档（Root 启动脚本与 service/boot-completed）：https://kernelsu.org/guide/module.html

> **编写说明**：本文件参照《已 Root 安卓手机部署 QQ Agent 完整教程》中已经实际成功的各组件、端口与故障经验，仅将其中可验证的部分用于无 Root 路线论证。上面给出的无 Root 命令是**待实机执行的实验指导**，不是伪装成已跑通的测试日志。

---

**版权与使用声明**：© 2026 **silent07137**。本报告的原创文字、论证结构、案例对照和教学编排保留作者权利；个人学习与非商业引用请注明来源，未经授权不得收费售卖、商业转载或包装成付费部署教程。第三方软件、官网内容、文献引用仍属于对应权利人并受各自许可约束。隐式溯源注释仅用于标示文档来源，不保证能够阻止删除署名或侵权。

<!-- end-provenance: S07137-WHALE-SHIZUKU-20261025-ED2 -->