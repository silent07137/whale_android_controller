# 已 Root 安卓手机部署 QQ Agent 完整教程

> **适用范围**：ARM64 安卓手机、已有 Root 权限；以 **KernelSU + Termux + Ubuntu 24.04 ARM64 chroot + Linux QQ + SnowLuma v2.1.1 + K0nd1us/QQ-agent 0.4** 为例。  
> **文档版本**：v1.0（2026-10-25）  
> **部署形式**：所有核心服务均在手机本机运行，不需要云服务器或电脑常驻。模型接口可以使用外部 API。  
> **本文不包含**：人设、模型提示词、私有 API Key、OneBot Token、QQ 登录数据或任何账号凭据。

> **原创整理与署名**：© 2026 **silent07137**。本教程由作者基于实际部署经验整理，仅供个人学习、交流和非商业研究；未经作者书面授权，不得将本文作为收费教程、商业培训资料或付费资源打包出售。转发请保留完整署名与出处。第三方软件及项目仍遵循各自许可协议。

> **文档授权**：© 2026 silent07137。本教程原创文字部分使用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 授权，转载请署名并保留溯源信息；商业使用需另行获得作者许可。第三方软件、商标和所引用材料不在此授权范围内。

<!-- provenance-id: S07137-WHALE-ROOT-20261025-ED2; author=silent07137; format=Markdown -->

## 目录

1. [方案介绍与完成标准](#1-方案介绍与完成标准)
2. [准备工作](#2-准备工作)
3. [安装 Termux 并确认 Root](#3-安装-termux-并确认-root)
4. [建立 Ubuntu ARM64 chroot](#4-建立-ubuntu-arm64-chroot)
5. [安装 Linux 图形桌面与 noVNC](#5-安装-linux-图形桌面与-novnc)
6. [安装并登录 Linux QQ](#6-安装并登录-linux-qq)
7. [安装 SnowLuma 并建立 OneBot](#7-安装-snowluma-并建立-onebot)
8. [安装 QQ Agent 0.4](#8-安装-qq-agent-04)
9. [一键启动与服务验收](#9-一键启动与服务验收)
10. [KernelSU 独立安卓控制台](#10-kernelsu-独立安卓控制台)
11. [后台保活及开机自启](#11-后台保活及开机自启)
12. [备份及恢复前检查](#12-备份及恢复前检查)
13. [常见故障排查](#13-常见故障排查)
14. [项目链接与安全提醒](#14-项目链接与安全提醒)

---

## 1. 方案介绍与完成标准

### 1.1 实际使用的架构

```text
安卓手机（ARM64 / 已 Root）
│
├── KernelSU
│   └── Root 授权、后台启动脚本、可选开机自启
│
├── Termux（主要用于初次安装及后期维护）
│   └── Ubuntu 24.04 ARM64 chroot
│       ├── Xvfb + Fluxbox：无实体屏幕的 Linux 图形桌面
│       ├── x11vnc + websockify/noVNC：手机浏览器查看 QQ 界面
│       ├── Linux QQ：实际登录机器人 QQ 账号
│       ├── SnowLuma：接入 QQ 并提供 OneBot v11
│       └── QQ Agent 0.4：收发事件、调用模型、保存会话和扩展
│
└── 大肥鱼控制台 APK（可选，但已在本次部署中验证）
    └── 通过 KernelSU Root 脚本启动 Ubuntu 和服务；不打开 Termux 窗口
```

### 1.2 成功标准

部署最终应满足以下条件：

- 浏览器能打开 noVNC `http://127.0.0.1:6081/vnc.html`。
- Linux QQ 已登录，进程持续运行。
- SnowLuma 管理界面能打开 `http://127.0.0.1:5099`，对应 QQ 的 OneBot 正常工作。
- QQ Agent 控制台能打开 `http://127.0.0.1:3210`，并显示 OneBot 已连接。
- **真正的最终验收：用另一个 QQ 账号发消息，机器人能收到并回复。** 单纯显示端口 `OK` 不等于消息链路正常。

本次真实部署已验证：独立 APK 能启动整套服务，三个 Web 端口正常，机器人可以回复 QQ 消息，最近任务隐藏正常；另外已有约 6 分钟的后台运行验证。**整夜保活及重启后自动恢复尚未作为已通过项目记录。**

### 1.3 路径与端口约定

| 项目 | 本教程使用的路径 / 地址 |
| --- | --- |
| Ubuntu 根文件系统 | `/data/local/chroot/ubuntu`（安卓宿主机） |
| Ubuntu 的 Root 目录 | `/root`（进入 chroot 之后） |
| Linux QQ 程序 | `/opt/QQ/qq` |
| SnowLuma 目录 | `/opt/whale/snowluma` |
| QQ Agent 0.4 目录 | `/opt/whale/QQ-agent-K0nd1us/0.4` |
| 一键启动脚本 | Ubuntu 内 `/root/start-whale.sh` |
| 一键停止脚本 | Ubuntu 内 `/root/stop-whale.sh` |
| KernelSU BusyBox | `/data/adb/ksu/bin/busybox` |
| 安卓控制台管理文件 | `/data/adb/whale-controller/` |
| noVNC | `127.0.0.1:6081` |
| VNC 服务 | `127.0.0.1:5900` |
| SnowLuma WebUI | `127.0.0.1:5099` |
| OneBot 正向 WebSocket | `ws://127.0.0.1:3001` |
| OneBot HTTP API | `http://127.0.0.1:3000` |
| QQ Agent 后台 | `http://127.0.0.1:3210` |

> 上表是**这台成功部署手机的配置**，不是所有设备或所有版本的固定默认值。特别是 OneBot 的端口、令牌和目录，应以自己的实际配置为准。

---

## 2. 准备工作

### 2.1 设备条件

- 手机 CPU 架构为 **aarch64 / ARM64**。
- 已 Root；以下以 **KernelSU** 为例，其它 Root 管理器需要自行调整对应路径。
- 建议至少 8 GB 内存，最好 12 GB 或更高；预留足够的存储空间供 Ubuntu、QQ、npm 依赖和聊天数据使用。
- 能访问软件发行页面、Ubuntu 软件仓库和模型 API。
- 建议使用独立 QQ 账号，并了解第三方 OneBot/QQ Hook 可能触发的账号风控风险。

### 2.2 软件下载来源

| 软件 | 建议来源 |
| --- | --- |
| Termux | https://github.com/termux/termux-app |
| Ubuntu Base ARM64 | https://cdimages.ubuntu.com/ubuntu-base/releases/24.04/release/ |
| Linux QQ（ARM64 `.deb`） | https://im.qq.com/index/#/linux |

> **下载入口更正**：QQ 官网 Linux 下载页为 https://im.qq.com/index/#/linux。它是网页入口，**不是 `.deb` 安装包直链**。请使用浏览器进入官网，在 Linux 下载区域选择 **ARM64 / aarch64** 的 `.deb` 安装包；不要直接对该网页运行 `apt install`、`wget` 后当作 `.deb` 安装。
| SnowLuma v2.1.1 | https://github.com/SnowLuma/SnowLuma/releases |
| QQ Agent 0.4 | https://github.com/K0nd1us/QQ-agent/tree/main/0.4 |
| KernelSU 使用说明 | https://kernelsu.org/guide/module.html |
| 本次安卓控制台工程 | https://github.com/silent07137/whale_android_controller （仓库权限由持有者决定） |

**注意：** QQ Agent 要使用 **`K0nd1us/QQ-agent` 仓库中的 `0.4` 目录**。不要误装另一个名称相近的 `shuang-ying/QQagent` 项目，它不是此次方案采用的程序。

---

## 3. 安装 Termux 并确认 Root

下文每个代码块会注明执行环境。不要把 Ubuntu 命令直接粘贴进安卓 Root Shell。

### 3.1 在【普通 Termux】执行

安装 Termux 后运行：

```bash
pkg update && pkg upgrade -y
pkg install -y curl wget git tar xz-utils unzip coreutils procps
termux-setup-storage
```

按系统要求授予存储权限。如果已经授权，可以略过 `termux-setup-storage`。

检查架构：

```bash
uname -m
```

预期为：

```text
aarch64
```

### 3.2 检查 Root 和 KernelSU BusyBox

仍在【普通 Termux】执行：

```bash
su -c 'id -u'
su -c '/data/adb/ksu/bin/busybox --help >/dev/null 2>&1 && echo KSU_BUSYBOX_OK'
```

预期分别显示 `0` 与 `KSU_BUSYBOX_OK`。如果 `su` 未授权，在 KernelSU 管理器中允许 Termux 使用 Root 权限。

> **重要经验**：不要把 `/data/data/com.termux/files/usr/bin/busybox` 直接复制到 `/data/adb/` 充当独立启动器的 BusyBox。某些 Termux 安装形式使用很小的可执行入口，还依赖 Termux 自己的动态库；复制后虽然文件存在，却可能执行失败。本次最终使用 **KernelSU 自带的 `/data/adb/ksu/bin/busybox`** 成功解决了这一问题。

---


> *文档署名：© 2026 silent07137 · 非商业学习交流使用 · 未经许可不得商业转载或售卖。*

<!-- doc-origin: s07137/root/chroot/a17; copyright © 2026 silent07137 -->

## 4. 建立 Ubuntu ARM64 chroot

此处使用 **真正的 chroot**，不是 `proot-distro`。Root 和 Linux QQ 图形环境会用到宿主机挂载权限。

### 4.1 下载 Ubuntu Base

在【普通 Termux】下载与本次部署相同系列的 **Ubuntu Base 24.04.4 ARM64**：

```bash
cd "$HOME"
BASE_URL='https://cdimages.ubuntu.com/ubuntu-base/releases/24.04/release'

curl -fL "$BASE_URL/ubuntu-base-24.04.4-base-arm64.tar.gz" \
  -o ubuntu-base.tar.gz
curl -fL "$BASE_URL/SHA256SUMS" -o SHA256SUMS

grep 'ubuntu-base-24.04.4-base-arm64.tar.gz' SHA256SUMS \
  | sed 's/ubuntu-base-24.04.4-base-arm64.tar.gz/ubuntu-base.tar.gz/' \
  | sha256sum -c -
```

看到 `ubuntu-base.tar.gz: OK` 才继续。如果官方目录后续不再保留这个版本，可以选择同系列更新的 24.04 ARM64 版本，同时修改文件名并重新校验。

### 4.2 解压到安卓数据分区

在【普通 Termux】执行以下 Root 命令：

```bash
su -c 'mkdir -p /data/local/chroot/ubuntu'

su -c '/data/adb/ksu/bin/busybox tar -xzf \
/data/data/com.termux/files/home/ubuntu-base.tar.gz \
-C /data/local/chroot/ubuntu'
```

验证根文件系统：

```bash
su -c 'ls -l /data/local/chroot/ubuntu/bin/bash /data/local/chroot/ubuntu/usr/bin/bash'
```

### 4.3 绑定系统设备目录

输入 `su`，进入【安卓 Root Shell】，然后运行：

```sh
ROOTFS=/data/local/chroot/ubuntu
BB=/data/adb/ksu/bin/busybox

mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/proc" "$ROOTFS/sys"

grep -q " $ROOTFS/dev " /proc/mounts || "$BB" mount --bind /dev "$ROOTFS/dev"
grep -q " $ROOTFS/dev/pts " /proc/mounts || "$BB" mount --bind /dev/pts "$ROOTFS/dev/pts"
grep -q " $ROOTFS/proc " /proc/mounts || "$BB" mount --bind /proc "$ROOTFS/proc"
grep -q " $ROOTFS/sys " /proc/mounts || "$BB" mount --bind /sys "$ROOTFS/sys"
```

如遇 `Operation not permitted`，先检查 Root 权限及内核挂载限制，不要直接关闭 SELinux。

### 4.4 进入 Ubuntu

仍在【安卓 Root Shell】运行：

```sh
/data/adb/ksu/bin/busybox chroot /data/local/chroot/ubuntu \
  /usr/bin/env -i \
  HOME=/root \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  TERM=xterm-256color \
  /bin/bash -l
```

此时命令行进入 Ubuntu 的 `root@localhost` 环境。执行：

```bash
cat /etc/os-release
uname -m
```

确认 Ubuntu 24.04、ARM64。

### 4.5 修复 DNS 并安装基础工具

以下开始都在【Ubuntu chroot】内执行：

```bash
cat /etc/resolv.conf
```

如果 DNS 为空，导致 `apt update` 报 `Temporary failure resolving`，可以在确认网络允许的情况下设置 DNS（示例）：

```bash
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
```

如果 `/etc/resolv.conf` 是指向不存在位置的链接，需要先修复链接；不同 ROM 或网络可能需要自己的 DNS 地址。

安装基础组件：

```bash
apt update
apt install -y \
  ca-certificates curl wget git tar unzip \
  procps psmisc iproute2 net-tools \
  dbus-x11 fontconfig fonts-noto-cjk
```

以后从 Termux 重新进入 Ubuntu，重复第 4.3 和 4.4 节即可（已经挂载的目录不需要重复挂载）。

---

## 5. 安装 Linux 图形桌面与 noVNC

QQ 是有图形界面的 Linux 客户端，但手机上的 chroot 没有实体 Linux 显示器，因此使用虚拟屏幕。

### 5.1 安装依赖

在【Ubuntu chroot】执行：

```bash
apt install -y \
  xvfb fluxbox x11vnc novnc websockify \
  libgbm1 libnss3 libasound2t64 libgtk-3-0 \
  libxshmfence1 libxdamage1 libdrm2 libxkbcommon0
```

### 5.2 为 VNC 创建密码

```bash
mkdir -p /root/.vnc
x11vnc -storepasswd
```

按提示设置 VNC 密码。不要把密码放进公开仓库。

### 5.3 启动虚拟桌面

在【Ubuntu chroot】依次执行：

```bash
nohup Xvfb :1 -screen 0 1280x720x24 -nolisten tcp \
  > /tmp/xvfb.log 2>&1 &

export DISPLAY=:1
nohup fluxbox > /tmp/fluxbox.log 2>&1 &

nohup x11vnc -display :1 -localhost -rfbport 5900 \
  -rfbauth /root/.vnc/passwd -forever -shared \
  > /tmp/x11vnc.log 2>&1 &

nohup websockify --web=/usr/share/novnc \
  127.0.0.1:6081 127.0.0.1:5900 \
  > /tmp/websockify.log 2>&1 &
```

手机浏览器打开：

```text
http://127.0.0.1:6081/vnc.html
```

连接成功后，应看到 Fluxbox 桌面。浏览器和 chroot 都在同一台手机，因此可以使用 `127.0.0.1`。

> VNC/noVNC 端口建议只绑定 `127.0.0.1`，不要暴露到公网或公共 Wi-Fi。此配置不需要长期开着浏览器页面；浏览器只是远程查看 Linux 桌面的窗口。

---

## 6. 安装并登录 Linux QQ

### 6.1 下载官方 ARM64 安装包

打开 QQ 官方下载页面：

https://im.qq.com/index/#/linux

下载 Linux **ARM64 / aarch64 `.deb`**。注意不要选 AMD64/x86_64 版本。

**下载方法**：在安卓浏览器打开上述官网，进入 Linux 版本下载区，选择 **ARM64 的 `.deb` 格式**，文件一般保存在 `Download`。安装前检查真实扩展名为 `.deb`；网页链接本身不能直接作为 Debian 安装包使用。

因为 QQ 安装包文件名会更新，本教程不写死版本号。假设下载到安卓的 `Download` 目录，将实际文件复制进 Ubuntu：

在【普通 Termux】执行（把尖括号中的文件名换成自己的真实文件名）：

```bash
su -c 'cp "/sdcard/Download/<实际QQ安装包文件名>.deb" \
  /data/local/chroot/ubuntu/root/linuxqq.deb'
```

### 6.2 在 Ubuntu 安装

在【Ubuntu chroot】执行：

```bash
# 核对是否下载到了适合 Ubuntu ARM64 的 Debian 包
dpkg-deb -f /root/linuxqq.deb Architecture
dpkg --print-architecture
# 两者均应为 arm64，核对后再安装
apt install -y /root/linuxqq.deb
ls -l /opt/QQ/qq
```

QQ 正常安装后程序通常位于 `/opt/QQ/qq`。

### 6.3 启动 QQ

确保第 5 节图形桌面已经运行。在【Ubuntu chroot】执行：

```bash
export DISPLAY=:1
nohup /opt/QQ/qq \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  > /tmp/linuxqq.log 2>&1 &
```

打开 noVNC 页面查看 QQ 登录二维码，完成登录。

**安全提醒**：`--no-sandbox` 是当前示例中以 Root 运行 Chromium/Electron 类 QQ 客户端的兼容参数，会降低隔离保护。本次部署采取了这种方式，但不应将它理解为通用安全最佳实践。不要在该环境中随意运行来源不明的 QQ 插件或脚本。

---


> *文档署名：© 2026 silent07137 · 非商业学习交流使用 · 未经许可不得商业转载或售卖。*

<!-- doc-origin: s07137/root/hook/a42; authored-teaching-material -->

## 7. 安装 SnowLuma 并建立 OneBot

SnowLuma 负责将已登录的 Linux QQ 接入 OneBot v11。这一层必须与 QQ 版本、ARM64 架构和注入环境兼容。

### 7.1 下载 ARM64 版本

本次验证的发行版本是 **SnowLuma v2.1.1 Linux ARM64**：

https://github.com/SnowLuma/SnowLuma/releases

在【Ubuntu chroot】可下载对应的完整版：

```bash
mkdir -p /opt/whale/snowluma
cd /tmp

curl -fL \
  'https://github.com/SnowLuma/SnowLuma/releases/download/v2.1.1/SnowLuma-v2.1.1-linux-arm64.tar.gz' \
  -o SnowLuma-linux-arm64.tar.gz

tar -tzf SnowLuma-linux-arm64.tar.gz | head -n 20
```

**先查看压缩包内部层级**，再解压，使运行目录最终包含 `index.mjs`（以及发行包提供的其它文件）：

```bash
tar -xzf /tmp/SnowLuma-linux-arm64.tar.gz \
  -C /opt/whale/snowluma

find /opt/whale/snowluma -maxdepth 3 \
  \( -name index.mjs -o -name launcher.sh \) -print
```

如果文件被放到额外的嵌套目录，应按实际解压结构调整；**不要未经检查就套用 `--strip-components=1`**。目标是 `/opt/whale/snowluma/index.mjs` 可以访问。

SnowLuma 完整版可使用发行包自带的 Node.js；本次手机环境后来也安装了系统 Node.js，并以 `node ./index.mjs` 运行。

### 7.2 安装 Node.js 24

QQ Agent 0.4 需要 Node.js 20 或更新版本；为了统一运行环境，本例使用 Node.js 24。安装方式以 NodeSource 当前说明为准。

在【Ubuntu chroot】执行：

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/setup_node24.sh
# 建议先查看脚本内容，再自行确认执行
bash /tmp/setup_node24.sh
apt install -y nodejs
node -v
npm -v
```

应看到 `v24.x` 或其它兼容版本。如果发行包已带完整 Node 环境，SnowLuma 本身可使用其 launcher，而 QQ Agent 仍需能找到兼容的系统 Node.js。

### 7.3 以正确顺序启动 SnowLuma 和 QQ

本次部署的关键经验是：**先准备 Xvfb，再启动 SnowLuma，最后启动 Linux QQ**。这样自动注入更稳定。

第一次配置时，如果 QQ 已在运行，可以先退出 QQ，再启动 SnowLuma。

在【Ubuntu chroot】执行：

```bash
cd /opt/whale/snowluma
export DISPLAY=:1

nohup env SNOWLUMA_HOOK_AUTOLOAD=1 \
  node ./index.mjs \
  > /tmp/snowluma.log 2>&1 &
```

随后在相同 `DISPLAY=:1` 中启动 Linux QQ（按第 6.3 节）。

> SnowLuma 发行包也提供 `launcher.sh`，首次同意协议、WebUI 初始化及具体启动参数可参考官方说明。设置 `SNOWLUMA_ACCEPT_EULA=1`、`SNOWLUMA_ACCEPT_PRIVACY=1` 等于代表使用者已经接受相关协议，不应在未阅读的情况下盲目写进公共一键脚本。

### 7.4 访问 SnowLuma 管理页面

手机浏览器打开：

```text
http://127.0.0.1:5099
```

初始化管理员账户、密码或验证码以实际启动日志为准：

```bash
tail -n 100 /tmp/snowluma.log
```

确认管理页面能够看到当前 QQ、Hook 已加载且 OneBot 接口已启用。

### 7.5 OneBot 接口记录

此次成功部署采用：

```text
正向 WebSocket：ws://127.0.0.1:3001
HTTP API：http://127.0.0.1:3000
```

在 SnowLuma 中核对实际端口和鉴权。**WebSocket Token 与 HTTP Token 可能不同**，不要想当然填成同一个。不要将 Token 分享给他人。

---

## 8. 安装 QQ Agent 0.4

### 8.1 拉取正确仓库

在【Ubuntu chroot】执行：

```bash
mkdir -p /opt/whale
cd /opt/whale

git clone https://github.com/K0nd1us/QQ-agent.git \
  QQ-agent-K0nd1us

cd /opt/whale/QQ-agent-K0nd1us/0.4
npm install
```

**必须进入 `0.4` 子目录**。不要直接在 GitHub 仓库根目录执行服务端启动命令。

### 8.2 启动无桌面服务端

在【Ubuntu chroot】执行：

```bash
cd /opt/whale/QQ-agent-K0nd1us/0.4
nohup npm run server > /tmp/qqagent.log 2>&1 &
```

这里的实际入口为 `node src/server.js`。手机浏览器打开：

```text
http://127.0.0.1:3210
```

QQ Agent 的 0.4 版本支持无桌面服务端运行，因此不需要再为它启动一个 Electron 窗口。

### 8.3 OneBot 与模型连接设置

在 QQ Agent 控制台中：

1. 找到 **OneBot** 设置页。
2. 填写 SnowLuma 的 **WebSocket 地址**、**HTTP API 地址**及对应鉴权信息。
3. 检查连接状态和读取到的 QQ 账号是否正确。
4. 在模型设置里填写自己合法拥有的 API Base URL、Key，并选择实际支持的模型。
5. 根据需要设置允许响应的群聊和好友，并测试消息收发。

本教程只说明**连接和运行方式**，不包含任何模型提示词、角色内容或私有密钥。

### 8.4 扩展文件位置

QQ Agent 0.4 的扩展主要分为：

```text
/opt/whale/QQ-agent-K0nd1us/0.4/
├── data/       # 运行配置、会话、记忆等
├── plugins/    # 确定性插件
└── skills/     # 由模型按工具描述调用的 Skill
```

上传 ZIP 后如果出现目录套目录，例如 `skills/xxx/xxx/skill.json`，应检查扩展清单和源码是否位于加载器识别的层级。不要把不可信扩展当作普通聊天数据；它们可能执行代码，Root 环境尤其需要谨慎。

---

## 9. 一键启动与服务验收

### 9.1 本次实际采用的启动顺序

```text
1. 检查并绑定 chroot 所需的 /dev、/dev/pts、/proc、/sys
2. 启动 Xvfb 显示 :1
3. 启动 Fluxbox
4. 启动 x11vnc 与 websockify/noVNC
5. 先启动 SnowLuma（SNOWLUMA_HOOK_AUTOLOAD=1）
6. 再启动 Linux QQ，使 SnowLuma 完成 Hook
7. 启动 QQ Agent 0.4
8. 检查 Web 端口、QQ 进程及真实消息收发
```

此次成功部署将 Ubuntu 的一键入口放在：

```text
/root/start-whale.sh
```

并配有对应的停止入口：

```text
/root/stop-whale.sh
```

**重要说明：** 一键脚本与服务进程名称、QQ 安装版本、当前登录状态有关。下面提供可理解的参考启动骨架，**不是对已验证脚本的逐字还原**。如果手机上已有运行正常的 `start-whale.sh`，不要直接用示例覆盖它。

### 9.2 Ubuntu 启动脚本参考骨架

在【Ubuntu chroot】先确认所需文件：

```bash
ls -l /opt/QQ/qq \
      /opt/whale/snowluma/index.mjs \
      /opt/whale/QQ-agent-K0nd1us/0.4/src/server.js
```

然后按照以下顺序组织自己的 `/root/start-whale.sh`（该示例适用于首次组装，要求已完成前面各阶段）：

```bash
#!/usr/bin/env bash
set -u
export DISPLAY=:1

mkdir -p /root/.vnc

if ! pgrep -x Xvfb >/dev/null; then
  nohup Xvfb :1 -screen 0 1280x720x24 -nolisten tcp \
    > /tmp/xvfb.log 2>&1 &
fi
sleep 1

if ! pgrep -x fluxbox >/dev/null; then
  nohup fluxbox > /tmp/fluxbox.log 2>&1 &
fi

if ! pgrep -x x11vnc >/dev/null; then
  nohup x11vnc -display :1 -localhost -rfbport 5900 \
    -rfbauth /root/.vnc/passwd -forever -shared \
    > /tmp/x11vnc.log 2>&1 &
fi

if ! curl -fsS --max-time 2 http://127.0.0.1:6081/vnc.html \
     -o /dev/null; then
  nohup websockify --web=/usr/share/novnc \
    127.0.0.1:6081 127.0.0.1:5900 \
    > /tmp/websockify.log 2>&1 &
fi

if ! curl -fsS --max-time 2 http://127.0.0.1:5099 \
     -o /dev/null; then
  (
    cd /opt/whale/snowluma || exit 1
    nohup env DISPLAY=:1 SNOWLUMA_HOOK_AUTOLOAD=1 \
      node ./index.mjs > /tmp/snowluma.log 2>&1 &
  )
fi
sleep 3

if ! pgrep -f '^/opt/QQ/qq([[:space:]]|$)' >/dev/null; then
  nohup /opt/QQ/qq --no-sandbox --disable-gpu \
    --disable-dev-shm-usage > /tmp/linuxqq.log 2>&1 &
fi
sleep 3

if ! curl -fsS --max-time 2 http://127.0.0.1:3210 \
     -o /dev/null; then
  (
    cd /opt/whale/QQ-agent-K0nd1us/0.4 || exit 1
    nohup npm run server > /tmp/qqagent.log 2>&1 &
  )
fi

echo '启动命令已提交，请检查状态与日志。'
```

示例中的端口检测不是严格的进程管理：正在启动但尚未监听端口时，重复点击仍有可能产生重复进程。稳定运行建议使用真实 PID/锁和健康检查逻辑。本次最终使用的是专门整理并已通过手机实测的一键脚本。

执行前赋予权限：

```bash
chmod 700 /root/start-whale.sh
bash /root/start-whale.sh
```

### 9.3 状态检查

在【Ubuntu chroot】执行：

```bash
for p in 6081 5099 3210; do
  echo "=== $p ==="
  curl -sSI --max-time 5 "http://127.0.0.1:$p/" | head -n 1
done

pgrep -af '/opt/QQ/qq|snowluma|src/server.js'
ss -lntp | grep -E ':(6081|5900|5099|3210|3000|3001)\b'
```

此外，在手机浏览器中分别打开三个 Web 页面，最后使用第二个 QQ 账号向机器人发送消息并核对回复。**这一步比只看进程号更可靠。**

### 9.4 查看日志

```bash
tail -n 80 /tmp/snowluma.log
tail -n 80 /tmp/qqagent.log
tail -n 80 /tmp/linuxqq.log
```

如果 QQ 能登录但没有回复，按「QQ → SnowLuma Hook → OneBot → QQ Agent → 模型 API」逐层排查。

---


> *文档署名：© 2026 silent07137 · 非商业学习交流使用 · 未经许可不得商业转载或售卖。*

<!-- doc-origin: s07137/root/apk/a73; redistribution-not-for-sale -->

## 10. KernelSU 独立安卓控制台

这一阶段属于**便利性增强**。完成前 9 节，机器人即已具备运行和收发消息的能力。独立 App 的目的是做到：从桌面一键启停，不打开 Termux 窗口；可隐藏控制台在「最近任务」中的卡片。

### 10.1 工程地址

本次制作并成功编译的工程：

https://github.com/silent07137/whale_android_controller

在 GitHub 仓库的 **Actions** 页面，选择最新成功的 `Build 大肥鱼控制台 APK`，下载 Artifacts 中的 `WhaleController-debug-apk`，解压得到 `app-debug.apk`。若仓库设置为私人仓库，访问者需要相应权限。

> 这是 Debug APK，更新时如遇签名不一致，可能需要卸载旧控制台再装新版。**不要卸载 Termux，更不要删除 Ubuntu chroot**。APK 只是控制入口，核心运行数据保存在 Ubuntu 目录。

### 10.2 KernelSU 授权与首次验证

1. 安装并打开「大肥鱼控制台」。
2. 在 KernelSU 管理器中给该 App 授予 Root 权限。
3. 点击「刷新运行状态」，确认 `BUSYBOX=ACCESSIBLE`、`UBUNTU_BASH=ACCESSIBLE`。
4. 点击「启动大肥鱼」，等待操作完成后刷新状态。
5. 核对如下字段：

```text
WANTED=ON
WATCH=ON
WATCH_PROCESS=RUNNING
BUSYBOX_PATH=/data/adb/ksu/bin/busybox
BUSYBOX=ACCESSIBLE
UBUNTU_BASH=ACCESSIBLE
PORT_6081=OK
PORT_5099=OK
PORT_3210=OK
QQ_PROCESS=OK
```

部分字段取决于当时的运行状态；端口正常之后，还需要做一次真实 QQ 消息回复测试。

### 10.3 为什么启动器不使用 Termux 的 BusyBox

这次真机调试发现：

```text
ROOT_UID=0
UBUNTU_BASH=ACCESSIBLE
BUSYBOX=NOT_ACCESSIBLE
```

尽管 Termux 里执行 `ls -l` 全部正常，独立 APK 所处的 KernelSU Root 环境仍不能正常执行 Termux 自有的 BusyBox。后来尝试复制 BusyBox 到 `/data/adb/whale-controller/`，文件存在但无法执行。最终将控制器修改为直接使用：

```text
/data/adb/ksu/bin/busybox
```

这次修改后，APK 成功启动 Ubuntu、QQ、SnowLuma 和 QQ Agent，且机器人确实完成了 QQ 回复测试。**不要再照搬中间失败版本中的 BusyBox 复制方案。**

### 10.4 最近任务隐藏

控制台的「后台隐藏」开关只会让**控制台 App 自己**不出现在安卓最近任务中；并不意味着后台服务获得了无限制保活，也不会自动清除曾手动打开的 Termux 卡片。

控制台的 Root 后台脚本不需要打开 Termux Activity，因此通过 APK 启动大肥鱼不会主动新建 Termux 最近任务卡片。

---

## 11. 后台保活及开机自启

### 11.1 当前使用方式

- 大肥鱼控制台「后台守护」使用 Root 脚本定时检查服务。
- 该版本逻辑约每 90 秒检测一次，连续失败两次尝试恢复。
- 手动点击「关闭大肥鱼」会清除“期望运行”标记，以避免守护立即把服务重新拉起来。
- 关闭 App 页面或开启「后台隐藏」，不会自动停止已经启动的 Ubuntu 服务。
- **锁屏长期在线、断线消息补收、重启自动恢复需要单独验收，不能仅从端口在线推断。**

### 11.2 不要同时运行两个守护器

初期曾使用过 Termux:Widget；后来已迁移到独立 APK。**卸载 Widget 不一定结束它此前建立的普通 Termux 守护进程**。

在【普通 Termux】清理旧监控，避免重复重启服务：

```bash
rm -f ~/.whale/boot-enabled
touch ~/.whale/stop.flag

if [ -f ~/.whale/watch.pid ]; then
  PID=$(cat ~/.whale/watch.pid)
  case "$PID" in
    *[!0-9]*|'') ;;
    *) kill -TERM "$PID" 2>/dev/null || true ;;
  esac
  rm -f ~/.whale/watch.pid
fi
```

这一段仅停止旧 Termux 守护器，不删除 Ubuntu 或 QQ Agent 数据。然后在新版控制台确认 `WATCH_PROCESS=RUNNING`。

### 11.3 KernelSU 开机自启

本工程使用 KernelSU 的通用开机脚本目录：

```text
/data/adb/boot-completed.d/
```

独立 App 的开机自启功能会安装受管理脚本；**必须先完成手动启动、停止、锁屏消息回复测试，再开启它**。首次解锁前某些数据目录可能不可用，需要让脚本等待数据可访问。

实际开机自启是否成功，应在设备重启后检查：

```text
WANTED=ON
WATCH_PROCESS=RUNNING
PORT_5099=OK
PORT_3210=OK
QQ_PROCESS=OK
```

然后用另一个 QQ 账号发消息验证。此项在本次记录中**尚未经过完整重启验收**，因此不标注为已完成。

### 11.4 Android 电池策略

给控制台和必要的后台组件允许后台运行，避免系统省电策略过早结束相关进程。Root 守护提高了恢复能力，但无法保证永不被杀。长期运行还会带来耗电、发热和电池寿命方面的影响。

---

## 12. 备份及恢复前检查

在修改系统、升级 QQ/SnowLuma、安装扩展之前，建议先备份会话、配置和启动脚本。

### 12.1 备份范围

本次部署的重要数据主要包括：

```text
/opt/whale/QQ-agent-K0nd1us/0.4/data
/opt/whale/QQ-agent-K0nd1us/0.4/skills
/opt/whale/QQ-agent-K0nd1us/0.4/plugins
/opt/whale/snowluma/data
/opt/whale/snowluma/config
/opt/whale/snowluma/.env（如有）
/root/start-whale.sh
/root/stop-whale.sh（如有）
/root/.config/QQ（如有）
/root/.local/share/QQ（如有）
/root/.vnc/passwd（如有）
```

备份时尽量先正常停止 QQ、SnowLuma、QQ Agent，使磁盘存档处于一致状态。不要直接分享未经加密的备份。

### 12.2 在 Ubuntu 创建压缩包

在【Ubuntu chroot，Bash】执行：

```bash
mkdir -p /root/whale-backups
FILE="/root/whale-backups/whale-$(date +%Y%m%d-%H%M%S).tar.gz"

paths=()
for p in \
  opt/whale/QQ-agent-K0nd1us/0.4/data \
  opt/whale/QQ-agent-K0nd1us/0.4/skills \
  opt/whale/QQ-agent-K0nd1us/0.4/plugins \
  opt/whale/snowluma/data \
  opt/whale/snowluma/config \
  opt/whale/snowluma/.env \
  root/start-whale.sh \
  root/stop-whale.sh \
  root/.config/QQ \
  root/.local/share/QQ \
  root/.vnc/passwd; do
  [ ! -e "/$p" ] || paths+=("$p")
done

[ "${#paths[@]}" -gt 0 ] || { echo '未找到可备份路径'; exit 1; }
tar -C / -czf "$FILE" "${paths[@]}"
ls -lh "$FILE"
```

**注意**：以上是核心配置/会话备份，不是整个 Ubuntu 系统镜像。完整系统迁移还需要处理软件包、挂载、Root/SELinux 差异等。

### 12.3 AES-256 加密

本次曾遇到 GPG 的 `Inappropriate ioctl for device`，原因是 chroot 终端无法正常使用交互式 pinentry。下面是此次成功使用的 `loopback` 思路：

```bash
read -rs -p '加密密码：' PASS; echo

printf '%s\n' "$PASS" | gpg \
  --batch --yes \
  --pinentry-mode loopback \
  --passphrase-fd 0 \
  --cipher-algo AES256 \
  --symmetric \
  --output "$FILE.gpg" \
  "$FILE"

unset PASS
ls -lh "$FILE.gpg"
```

请自己妥善保管密码，不要把密码写到 GitHub、聊天截图或命令参数中。

### 12.4 复制到安卓 Download 并核对

退出 Ubuntu 回到【Termux】后执行：

```bash
su -c 'cp -v /data/local/chroot/ubuntu/root/whale-backups/*.gpg \
  /storage/emulated/0/Download/'
```

再对比源文件与复制文件的 SHA256；两行摘要一致说明复制时未发生字节差异。最好额外进行一次解密和压缩包内容检查，并将加密备份放在手机之外的另一处存储。

> **切记**：`/root/whale-backups` 是 Ubuntu 内的路径；退出 chroot 后，安卓宿主机的路径应写成 `/data/local/chroot/ubuntu/root/whale-backups`。

---


> *文档署名：© 2026 silent07137 · 非商业学习交流使用 · 未经许可不得商业转载或售卖。*

<!-- doc-origin: s07137/root/diagnostics/a91; preserve-attribution -->

## 13. 常见故障排查

### 13.1 Root 正常，但 APK 显示 `UBUNTU=NOT_FOUND`

先在普通 Termux 里检查实际文件：

```bash
su -c 'for p in \
/data/adb/ksu/bin/busybox \
/data/local/chroot/ubuntu/bin/bash \
/data/local/chroot/ubuntu/usr/bin/bash \
/data/local/chroot/ubuntu/root/start-whale.sh; do \
  if [ -x "$p" ]; then echo "OK: $p"; else echo "FAIL: $p"; fi; \
done'
```

再打开 APK 的状态与「最近操作」。如果 `ROOT_UID=0`，但 `BUSYBOX=NOT_ACCESSIBLE`，优先确认使用的是 **KernelSU 自带 BusyBox**，而不是 Termux 私有路径中的 BusyBox。

### 13.2 BusyBox 文件存在，但无法执行

`ls -l` 只能证实文件存在，不能证明可独立运行。验证：

```bash
su -c '/data/adb/ksu/bin/busybox --help >/dev/null 2>&1 && echo OK'
```

出现 `OK` 才算通过。不要将 Termux 的小型 BusyBox 入口直接复制过去。

### 13.3 SnowLuma WebUI 有多个 QQ 条目或 `COMPONENT_LOAD_FAILED`

本次曾出现 SnowLuma 里多个异常 QQ 条目。通过结束异常 QQ 进程、保持 SnowLuma 先运行、再启动 QQ 后恢复。重点检查：

- 是否有旧 QQ 主进程没有退出。
- SnowLuma 和 QQ 的启动先后顺序。
- `SNOWLUMA_HOOK_AUTOLOAD=1` 是否生效。
- SnowLuma native hook 与当前 Linux QQ 版本是否兼容。

不要在未备份时随意删除 QQ 登录目录。

### 13.4 QQ Agent 页面在线，但机器人不回复

依次检查：

1. QQ 是否仍然登录；
2. SnowLuma 是否确实 Hook 到当前 QQ；
3. OneBot WebSocket、HTTP 与各自 Token 是否正确；
4. QQ Agent 是否对目标群/好友启用了响应；
5. 模型 API 是否正常、是否有额度或鉴权问题。

可以检查日志：

```bash
tail -n 100 /tmp/snowluma.log
tail -n 100 /tmp/qqagent.log
```

### 13.5 模型报 `401 Unauthorized`

通常属于模型 API 地址、Key、提供商格式或授权问题，**不是 QQ 登录密码的问题**。在控制台核对 Base URL、Key 与模型，然后使用应用自带的连接测试；勿在截图或日志中泄露 Key。

### 13.6 `apt update` 无法解析域名

检查 `/etc/resolv.conf`、网络联通及 Ubuntu 内的 DNS 配置，必要时按第 4.5 节修复。不要把移动网络/APN 故障误诊为 apt 软件源故障。

### 13.7 `libasound2` 不存在

Ubuntu 24.04 常用的兼容库包名为 `libasound2t64`。先查 `apt-cache policy libasound2t64`，按当前系统仓库提供的包安装。

### 13.8 noVNC 白屏、QQ 不显示

检查：

```bash
pgrep -af 'Xvfb|fluxbox|x11vnc|websockify|/opt/QQ/qq'
tail -n 80 /tmp/xvfb.log
tail -n 80 /tmp/x11vnc.log
tail -n 80 /tmp/websockify.log
```

确保图形组件和 Linux QQ 均使用同一个 `DISPLAY=:1`。

### 13.9 APP 端口正常，但 `WATCH_PROCESS=STOPPED`
说明前台服务可能在运行，**但 Root 守护进程没有持续监控**。检查是否开启了守护开关、是否存在新旧监控冲突，以及 `/data/adb/whale-controller/watch.log`。

### 13.10 GitHub Actions 编译 APK 失败

本次经历了三类典型错误：

- `Failed to find package 'tools'`：Android SDK 初始化流程尝试安装过时的工具包。
- `sdkmanager: command not found`：SDK 工具未加入 PATH。
- Java `cannot find symbol: setTextAllCaps`：按钮方法名写错，修正为 `setAllCaps(false)`。

以上问题已经在本次控制台仓库的后续提交中修复。遇到新失败时看对应 Actions 的 **失败步骤日志**，不要无区别重复点击 Run workflow。

---

## 14. 项目链接与安全提醒

### 14.1 参考文档

- Termux 官方项目：https://github.com/termux/termux-app
- Ubuntu Base 官方发行目录：https://cdimages.ubuntu.com/ubuntu-base/releases/24.04/release/
- QQ Linux 官方下载：https://im.qq.com/index/#/linux
- SnowLuma 发行版：https://github.com/SnowLuma/SnowLuma/releases
- SnowLuma Linux 手动部署说明：https://snowluma.github.io/zh/docs/guide/deploy/linux-manual
- QQ Agent 0.4 原项目说明：https://github.com/K0nd1us/QQ-agent/blob/main/0.4/README.md
- KernelSU 开机脚本机制：https://kernelsu.org/guide/module.html
- 大肥鱼控制台工程：https://github.com/silent07137/whale_android_controller

### 14.2 安全清单

- 不公开 QQ 会话、扫码登录信息、SnowLuma/OneBot Token、模型 API Key。
- 端口尽量监听 `127.0.0.1`；不要把 Web 管理界面裸露在公网。
- 不上传 `data/`、QQ 账号目录、日志、`.env` 或完整备份到公开 GitHub 仓库。
- 需要 Root 的组件越少越好；本方案中 QQ 以 `--no-sandbox` 运行属于兼容性折中。
- 第三方插件及 Skill 可能执行代码，安装前应审查来源和权限。
- 每次升级 QQ、SnowLuma 或 QQ Agent 前先备份，再进行真实消息收发测试。
- KernelSU 保活不等于百分百在线；离线期间消息能否补收取决于 QQ/OneBot/Agent 的实际能力。

---

## 最终部署记录

**已完成并经过这次真机测试：**

- ARM64 Ubuntu 24.04 chroot 运行；
- Xvfb + Fluxbox + VNC/noVNC；
- Linux QQ 登录；
- SnowLuma v2.1.1 Hook 与 OneBot；
- K0nd1us QQ Agent 0.4 无桌面服务端运行；
- 手机本地 6081 / 5099 / 3210 管理页面可访问；
- KernelSU 独立安卓控制台一键启动，不主动打开 Termux；
- 控制台最近任务隐藏；
- QQ 消息能够实际收到并回复；
- AES-256 加密备份已创建并复制到安卓存储。

**仍需单独验证：** 较长时间锁屏在线、整夜保活、手动停止后守护是否完全停止、KernelSU 开机自启、设备重启后 QQ 是否自动恢复消息接收。

> 这是一份 **Root 环境部署教程**。若未来要制作无 Root 版，需要重新设计 QQ 运行环境和 Hook 方案，不能简单去掉 `su` 或把 chroot 替换成 proot 就假定功能不变。

---

**版权与使用声明**：© 2026 **silent07137**。本教程的原创文字组织、案例分析和教学编排由作者保留权利；未经授权不得以售卖、收费课程或商业资料包的方式利用本文。个人学习和非商业引用请注明作者及来源。本文涉及的 QQ、SnowLuma、QQ Agent、KernelSU 等第三方项目的商标、软件与源代码权利及许可不受本声明影响。水印是作者署名与来源标识，不能单独代替版权登记或证明侵权。

<!-- end-provenance: S07137-WHALE-ROOT-20261025-ED2 -->