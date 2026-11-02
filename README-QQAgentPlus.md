# 小鲸鱼控制台（QQAgentPlus）· Android APK v0.1.2

这是在旧「大肥鱼控制台」源码基础上制作的**独立安卓 App**。注意：该功能分支不应直接覆盖旧 App。新的 applicationId 是 cn.whale.qqaplus.controller，与原来的 cn.whale.controller 同时安装。

## 管理范围与真实路径

- Android 设备：Redmi K90 Ultra，KernelSU Root
- Ubuntu 真 chroot：/data/local/chroot/ubuntu
- QQAgentPlus：/root/qqagentplus-lab/app
- QQAgentPlus 数据：/root/qqagentplus-lab/data
- SnowLuma 2.1.1：/root/qqagentplus-lab/snowluma-new
- 新号登录数据：/root/qqagentplus-lab/qq-home
- VNC 密码：/root/qqagentplus-lab/vnc.pass
- Ubuntu 运行脚本：/root/qqagentplus-lab/control/runner.sh
- KernelSU 控制脚本：/data/adb/qqaplus-controller/controller.sh

本 App 不自带第三方 QQ、SnowLuma 或 QQAgentPlus 程序，不需要安装第二份 Ubuntu。不会读取或迁移「汐」的记忆和账号。

## 可控服务

1. Xvfb :2、Fluxbox、x11vnc :5902、noVNC :6082。
2. Linux QQ：独立 HOME 与 XDG_* 环境变量，当前 Root 实验运行方式暂时使用 --no-sandbox。
3. SnowLuma：5100 WebUI、OneBot 3000/3001；保持 HOOK_AUTOLOAD=0，不会扫描并自动注入其他 QQ 账号。
4. QQAgentPlus：43210，指定数据目录，端口 3000/3001；不强制将现有 Active / Observe 模式清零。

界面有启动、停止、状态、日志、守护开关、开机自启开关和三个网页入口。首次打开会请求 KernelSU Root 并安装控制脚本，**不会自动启动已有进程**。守护与开机自启均默认关闭。

## 构建 / 获取 APK

前往本仓库 GitHub Actions，选择名称为 “Build 小鲸鱼 QQAgentPlus Controller APK” 的运行，下载其中的 “SmallWhale-QQAgentPlus-v0.1.2-debug-apk” artifact，并解压安装 app-debug.apk。

该工作流由 feature/qqagentplus-controller 分支的 Push 触发。不需要修改 XiAgent Mobile 项目。

注：debug 签名在不同构建环境可能变化；本 App 使用全新包名，不会覆盖旧 WhaleController，但将来升级本 App 需保持同一签名或进行安装迁移。

## 首次验收（强烈建议按顺序）

1. 备份 /root/qqagentplus-lab/data 和 qq-home，核实旧「大肥鱼控制台」未启用开机自启。
2. 安装 APK 后在 KernelSU 授予它 Root。打开后点击“刷新运行状态”，确认 43210、5100、QQ 进程。
3. **不要立即重启手机或打开自启。** 先点击“正常停止”，确认只停止小鲸鱼新号进程，旧账号和 XiAgent Mobile 不受影响。
4. 点击“启动小鲸鱼”，核对 43210、5100、6082 的可访问性，确认 QQ 登录状态；打开 SnowLuma 手动注入该新号 QQ 主进程（如有需要）。
5. 通过白名单私聊测试 QQAgentPlus 能收到、思考并发送消息。仅端口监听不等于完整消息链路可用。
6. 先在屏幕关闭 10 分钟后检查状态；之后再按需开启守护（每 120 秒检查，连续失败两次触发恢复，单次守护进程最多恢复三次）。
7. **最后**开启开机自启，重启设备后验证 Qt/QQ 登录、SnowLuma 的手动注入以及 OneBot 真正收发。

## 当前限制

- 由于 SnowLuma 禁用了全局自动注入，**重启 QQ / 重启手机后可能需要手动注入**。本 APK 不伪称已实现全链路无人值守在线。
- 守护只根据独立 QQ 进程和 Agent/SnowLuma 端口判定基础健康，不读取私聊消息，也不验证模型回复质量。
- 手动控制中使用 PID 和环境变量、工作目录进行匹配，减少误停其他 QQ 进程的风险；首次运行时要核对诊断状态。
- Ubuntu /dev/shm 会在启动时尝试重新挂载，兼容先前的临时修复。
- Root、在 Linux QQ 运行 --no-sandbox、以及暴露管理 Token 均有安全风险。所有 Web 入口限于本机；不要公开日志中的密码、Token 和 QQ 资料。
- 未在 Redmi K90 Ultra 做过本版本 APK 真机验证；Actions 绿灯只表示静态检查和构建通过。

## 独立性与回滚

Android 包名：cn.whale.qqaplus.controller；Root 状态目录：/data/adb/qqaplus-controller；开机脚本：/data/adb/boot-completed.d/98-qqaplus-controller.sh。

旧 WhaleController 使用 cn.whale.controller、/data/adb/whale-controller，彼此隔离。本 App 发现旧控制台仍开启自启时会拒绝开启自己的自启，避免旧 QQAgent 与新 QQAgentPlus 开机争抢服务。

**卸载本 App 不会删除 Ubuntu 数据**。卸载前务必在界面关闭“开机自启”和“后台守护”；Root 控制脚本和已运行的 Ubuntu 进程不会因卸载 App 自动消失。

此分支仅为实验预览，不代表 SnowLuma、QQAgentPlus、QQ 或腾讯官方支持。

## v0.1.2 Root 权限错误提示

如果看到 `Cannot run program "su": error=13, Permission denied`，先到 KernelSU → 超级用户，将 `cn.whale.qqaplus.controller` 设为允许。KernelSU 不会自动继承其他 App 的 Root 授权。回来点击「重新检查 KernelSU 授权」，不需要修改 `su` 文件权限、SELinux 或重装 Ubuntu。

`su` 仍然不能执行时，请先检查 KernelSU 中此包名的 Root Profile 是否被限制，不要开启全局 Permissive。
