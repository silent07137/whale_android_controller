#!/system/bin/sh
# 大肥鱼控制台 KernelSU Root 管理脚本。只能通过显式操作启动或关闭。
# Android root 端运行，不会打开 Termux Activity。
set -u
umask 077
STATE=/data/adb/whale-controller
SELF="$STATE/controller.sh"
# KernelSU 官方支持 boot-completed.d，在 Android 启动完成后执行。
BOOTFILE=/data/adb/boot-completed.d/99-whale-controller.sh
# 仅用于清理本控制台 v0.1 可能遗留的旧版开机脚本。
LEGACY_BOOTFILE=/data/adb/service.d/99-whale-controller.sh
ROOTFS=/data/local/chroot/ubuntu
BB=/data/adb/ksu/bin/busybox
AGENT_DIR=/opt/whale/QQ-agent-K0nd1us/0.4
DIARY_DIR=$AGENT_DIR/whale-diary

error() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || error '需要 Root 授权'

install() {
  mkdir -p "$STATE" || error "无法创建 $STATE"
  chmod 700 "$STATE"
  [ -r "$0" ] || error '安装源文件无法读取'
  # 如果正在运行稳定脚本，复制到临时位置后再原子替换。
  cp "$0" "$STATE/controller.sh.new" || error '复制启动脚本失败'
  chmod 700 "$STATE/controller.sh.new"
  mv -f "$STATE/controller.sh.new" "$SELF"
  if [ ! -e "$STATE/watch-configured" ]; then
    touch "$STATE/watch-enabled" "$STATE/watch-configured"
  fi
  echo 'CONTROLLER_INSTALLED=1'
}

check_rootfs() {
  [ -x "$BB" ] && "$BB" --help >/dev/null 2>&1 || error "KernelSU BusyBox 无法执行：$BB"
  [ -x "$ROOTFS/bin/bash" ] || error "缺少 Ubuntu chroot：$ROOTFS"
}
mounted() { grep -q " $1 " /proc/mounts; }
prepare() {
  check_rootfs
  mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/proc" "$ROOTFS/sys" || error '准备目录失败'
  mounted "$ROOTFS/dev" || "$BB" mount --bind /dev "$ROOTFS/dev" || error '挂载 /dev 失败'
  mounted "$ROOTFS/dev/pts" || "$BB" mount --bind /dev/pts "$ROOTFS/dev/pts" || error '挂载 /dev/pts 失败'
  mounted "$ROOTFS/proc" || "$BB" mount --bind /proc "$ROOTFS/proc" || error '挂载 /proc 失败'
  mounted "$ROOTFS/sys" || "$BB" mount --bind /sys "$ROOTFS/sys" || error '挂载 /sys 失败'
}
ubuntu() {
  "$BB" chroot "$ROOTFS" /usr/bin/env -i \
    HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=xterm-256color /bin/bash -c "$1"
}
# 探索日记是独立的只读服务；只使用 127.0.0.1 端口，不读取 QQ 凭据。
diary_installed() {
  [ -f "$ROOTFS$DIARY_DIR/server.py" ] && [ -f "$ROOTFS$DIARY_DIR/start.sh" ] && [ -f "$ROOTFS$DIARY_DIR/url.sh" ]
}
diary_probe() {
  ubuntu 'curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:3222/health' >/dev/null 2>&1
}
diary_status() {
  if diary_installed; then echo 'DIARY_INSTALLED=YES'; else echo 'DIARY_INSTALLED=NO'; fi
  if diary_probe; then echo 'DIARY_PORT=OK'; else echo 'DIARY_PORT=DOWN'; fi
  if [ -f "$STATE/diary-autostart" ]; then echo 'DIARY_AUTOSTART=ON'; else echo 'DIARY_AUTOSTART=OFF'; fi
  for item in 'whale-explorer:EXPLORER_SKILL' 'whale-web-reader:WEB_READER_SKILL' 'video-watch:VIDEO_SKILL'; do
    name=${item%%:*}
    label=${item#*:}
    if [ -f "$ROOTFS$AGENT_DIR/skills/$name/skill.json" ]; then
      echo "$label=INSTALLED"
    else
      echo "$label=NOT_FOUND"
    fi
  done
}
diary_start() {
  prepare
  diary_installed || error '探索日记未安装，请先在 Ubuntu 中安装 whale-diary v0.1.1'
  if ! diary_probe; then
    # 原版 start.sh 在 /proc 未就绪时可能误判，因此以真实 HTTP 健康接口为准。
    ubuntu "sh '$DIARY_DIR/start.sh' >/dev/null 2>&1" || true
    i=0
    while ! diary_probe; do
      i=$((i + 1))
      [ "$i" -lt 8 ] || error '探索日记启动失败；请查看日记日志'
      sleep 1
    done
  fi
  echo 'DIARY_RUNNING=YES'
}
diary_open() {
  diary_start
  url=$(ubuntu "sh '$DIARY_DIR/url.sh'") || error '探索日记访问密钥未就绪'
  case "$url" in
    http://127.0.0.1:3222/\#*) echo "DIARY_URL=$url" ;;
    *) error '探索日记网址格式无效，拒绝打开非本机地址' ;;
  esac
}
diary_stop() {
  prepare
  if ! diary_installed; then echo 'DIARY_RUNNING=NO'; return 0; fi
  ubuntu "sh '$DIARY_DIR/stop.sh'" || error '无法停止探索日记，请查看日志'
  echo 'DIARY_STOP_REQUESTED=YES'
}
summary() {
  prepare
  echo 'DEVICE_SUMMARY=ANDROID_HOST_MEMORY_AND_ROOTFS_STORAGE'
  ubuntu 'awk "/MemTotal:/ {total=int(\$2/1024)} /MemAvailable:/ {free=int(\$2/1024)} END {printf \"TOTAL_RAM_MB=%d\\nAVAILABLE_RAM_MB=%d\\n\",total,free}" /proc/meminfo'
  ubuntu 'df -h / | tail -n 1' | while IFS= read -r line; do echo "ROOTFS_DISK=$line"; done
}
watch_pid() {
  [ -f "$STATE/watch.pid" ] || return 1
  pid=$(cat "$STATE/watch.pid" 2>/dev/null) || return 1
  case "$pid" in *[!0-9]*|'') return 1 ;; esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  # 避免由于 PID 复用误杀其他程序。
  tr '\000' ' ' < "/proc/$pid/cmdline" | grep -q "controller.sh watch"
}
stop_watch() {
  if watch_pid; then
    pid=$(cat "$STATE/watch.pid")
    kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -f "$STATE/watch.pid"
}
spawn_watch() {
  [ -e "$STATE/watch-enabled" ] || return 0
  watch_pid && return 0
  # 所有标准流重定向，确保启动器 Activity 退出后仍独立运行。
  "$BB" nohup /system/bin/sh "$SELF" watch \
    </dev/null >>"$STATE/watch.log" 2>&1 &
  echo $! > "$STATE/watch.pid"
}
start() {
  prepare
  [ -f "$ROOTFS/root/start-whale.sh" ] || error '找不到 /root/start-whale.sh'
  touch "$STATE/wanted"
  echo '正在启动现有 Ubuntu 服务……'
  if ! ubuntu 'bash /root/start-whale.sh'; then
    echo 'WARN: 启动脚本返回非零值，请查看日志' >&2
  fi
  if [ -f "$STATE/diary-autostart" ]; then
    diary_start || echo 'WARN: 探索日记自动启动失败，主服务不受影响' >&2
  fi
  spawn_watch
  echo 'START_COMMAND_COMPLETED=1'
}
stop() {
  rm -f "$STATE/wanted"
  stop_watch
  prepare
  if [ -f "$ROOTFS/root/stop-whale.sh" ]; then
    ubuntu 'bash /root/stop-whale.sh' || true
  else
    echo 'ERROR: 没找到 /root/stop-whale.sh，已停止守护但未关闭全部服务' >&2
    exit 1
  fi
  echo 'STOP_COMMAND_COMPLETED=1'
}
health() {
  # 返回 0 表示三个面板与 QQ 主进程均存在。
  ubuntu '
    fail=0
    for p in 6081 5099 3210; do
      if curl -fsS --max-time 3 -o /dev/null "http://127.0.0.1:$p/"; then
        echo "PORT_$p=OK"
      else
        echo "PORT_$p=DOWN"
        fail=1
      fi
    done
    if pgrep -f "^/opt/QQ/qq( |$)" >/dev/null; then
      echo "QQ_PROCESS=OK"
    else
      echo "QQ_PROCESS=DOWN"
      fail=1
    fi
    exit "$fail"
  '
}
status() {
  if [ -e "$STATE/wanted" ]; then echo 'WANTED=ON'; else echo 'WANTED=OFF'; fi
  if [ -e "$STATE/watch-enabled" ]; then echo 'WATCH=ON'; else echo 'WATCH=OFF'; fi
  if watch_pid; then echo 'WATCH_PROCESS=RUNNING'; else echo 'WATCH_PROCESS=STOPPED'; fi
  if [ -e "$STATE/autoboot" ]; then echo 'AUTOBOOT=ON'; else echo 'AUTOBOOT=OFF'; fi
  # File visibility can differ between Termux's su shell and the controller
  # APK's KernelSU su shell (mount namespace and/or SELinux context).
  # Report each check separately instead of a misleading single NOT_FOUND.
  echo "BUSYBOX_PATH=$BB"
  if [ -x "$BB" ] && "$BB" --help >/dev/null 2>&1; then
    echo 'BUSYBOX=ACCESSIBLE'
  else
    echo 'BUSYBOX=NOT_ACCESSIBLE'
    echo 'BUSYBOX_INSTALL_HINT=Check KernelSU internal BusyBox at /data/adb/ksu/bin/busybox'
  fi
  if [ -x "$ROOTFS/bin/bash" ]; then
    echo 'UBUNTU_BASH=ACCESSIBLE'
  else
    echo 'UBUNTU_BASH=NOT_ACCESSIBLE'
  fi
  if [ ! -x "$BB" ] || ! "$BB" --help >/dev/null 2>&1 || [ ! -x "$ROOTFS/bin/bash" ]; then
    echo 'UBUNTU=NOT_ACCESSIBLE_FROM_APP'
    echo "ROOT_UID=$(id -u 2>/dev/null)"
    echo "ROOT_SELINUX_CONTEXT=$(id -Z 2>/dev/null || echo unknown)"
    for p in /data/adb/ksu/bin/busybox \
             /data/local/chroot/ubuntu/bin/bash \
             /data/local/chroot/ubuntu/usr/bin/bash; do
      if [ -e "$p" ]; then
        echo "FILE_EXISTS=$p"
      else
        echo "FILE_MISSING_OR_INVISIBLE=$p"
      fi
      ls -ld "$p" 2>&1 || true
    done
    return 1
  fi
  prepare
  health
  health_rc=$?
  diary_status
  return "$health_rc"
}
watch() {
  trap 'exit 0' TERM INT
  fails=0
  echo "[$(date)] watchdog started"
  while [ -e "$STATE/wanted" ] && [ -e "$STATE/watch-enabled" ]; do
    sleep 90 & wait $! || exit 0
    [ -e "$STATE/wanted" ] && [ -e "$STATE/watch-enabled" ] || break
    if health >/dev/null 2>&1; then
      fails=0
    else
      fails=$((fails + 1))
      echo "[$(date)] health miss $fails/2"
      if [ "$fails" -ge 2 ]; then
        echo "[$(date)] restarting services"
        start >> "$STATE/watch.log" 2>&1 || true
        fails=0
      fi
    fi
  done
  echo "[$(date)] watchdog stopped"
}
write_boot() {
  mkdir -p /data/adb/boot-completed.d || error '无法创建 KernelSU boot-completed.d 目录'
  if [ -e "$BOOTFILE" ] && ! grep -q '^# WHALE_CONTROLLER_MANAGED$' "$BOOTFILE"; then
    error "检测到同名非本程序开机脚本，拒绝覆盖：$BOOTFILE"
  fi
  # 清理本程序 v0.1 遗留的 service.d 脚本，避免重启后启动两次。
  if [ -f "$LEGACY_BOOTFILE" ] && grep -q '^# WHALE_CONTROLLER_MANAGED$' "$LEGACY_BOOTFILE"; then
    rm -f "$LEGACY_BOOTFILE"
  fi
  cat > "$BOOTFILE" <<'BOOT'
#!/system/bin/sh
# WHALE_CONTROLLER_MANAGED
BASE=/data/adb/whale-controller
[ -f "$BASE/autoboot" ] || exit 0
# KernelSU boot-completed.d 仍可能先于用户解锁执行，
# 等待 Termux 凭据加密存储解锁及 Ubuntu chroot 可用。
i=0
while [ ! -x /data/adb/ksu/bin/busybox ] || [ ! -x /data/local/chroot/ubuntu/bin/bash ]; do
  [ -f "$BASE/autoboot" ] || exit 0
  i=$((i + 1))
  if [ "$i" -ge 720 ]; then
    echo "[$(date)] 等待用户解锁/文件可用超时，取消本次自动启动" >> "$BASE/boot.log"
    exit 1
  fi
  sleep 5
done
[ -f "$BASE/autoboot" ] || exit 0
exec /system/bin/sh "$BASE/controller.sh" start >> "$BASE/boot.log" 2>&1
BOOT
  chmod 700 "$BOOTFILE"
}

action=${1:-status}
case "$action" in
  install) install ;;
  start) start ;;
  stop) stop ;;
  status) status ;;
  watch) watch ;;
  watch-on)
    mkdir -p "$STATE"
    touch "$STATE/watch-enabled"
    [ -e "$STATE/wanted" ] && spawn_watch
    echo 'WATCH=ON'
    ;;
  watch-off)
    rm -f "$STATE/watch-enabled"
    stop_watch
    echo 'WATCH=OFF'
    ;;
  boot-on)
    mkdir -p "$STATE"
    write_boot
    touch "$STATE/autoboot"
    echo 'AUTOBOOT=ON'
    ;;
  boot-off)
    rm -f "$STATE/autoboot"
    if [ -e "$BOOTFILE" ] && grep -q '^# WHALE_CONTROLLER_MANAGED$' "$BOOTFILE"; then
      rm -f "$BOOTFILE"
    fi
    if [ -e "$LEGACY_BOOTFILE" ] && grep -q '^# WHALE_CONTROLLER_MANAGED$' "$LEGACY_BOOTFILE"; then
      rm -f "$LEGACY_BOOTFILE"
    fi
    echo 'AUTOBOOT=OFF'
    ;;
  logs)
    tail -n 50 "$STATE/watch.log" 2>/dev/null || echo '暂无守护日志'
    ;;
  logs-boot)
    tail -n 60 "$STATE/boot.log" 2>/dev/null || echo '暂无开机日志'
    ;;
  logs-diary)
    tail -n 50 "$ROOTFS$DIARY_DIR/server.log" 2>/dev/null || echo '暂无探索日记日志'
    ;;
  summary) summary ;;
  diary-status) prepare; diary_status ;;
  diary-open) diary_open ;;
  diary-start) diary_start ;;
  diary-stop) diary_stop ;;
  diary-auto-on)
    mkdir -p "$STATE"; touch "$STATE/diary-autostart"; echo 'DIARY_AUTOSTART=ON' ;;
  diary-auto-off)
    rm -f "$STATE/diary-autostart"; echo 'DIARY_AUTOSTART=OFF' ;;
  *) error '支持：install start stop status watch-on watch-off boot-on boot-off logs summary diary-open diary-start diary-stop diary-auto-on diary-auto-off logs-diary logs-boot' ;;
esac
