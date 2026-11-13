#!/system/bin/sh
# 知遥控制台，独立于 Termux。只管理 MaiBot，不启动 QQAgent。
set -u
umask 077
STATE=/data/adb/zhiy-controller
SELF=$STATE/controller.sh
CONF=$STATE/config.sh
ROOTFS=/data/local/chroot/ubuntu
BB=/data/adb/ksu/bin/busybox
BOOTFILE=/data/adb/boot-completed.d/99-zhiy-controller.sh
mkdir -p "$STATE" || exit 1
chmod 700 "$STATE"
fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail '需要 Root'
MAIBOT_DIR=/root/maibot-whale
MAIBOT_BIN=/root/.local/bin/maibot
MAIBOT_PORT=8001
# 仅在 Root 私有文件内自定义，不能填写 QQAgent 旧启动脚本。
[ -f "$CONF" ] && . "$CONF"
install() {
  cp "$0" "$SELF.new" && chmod 700 "$SELF.new" && mv -f "$SELF.new" "$SELF" || fail '安装失败'
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<'CONFIG'
MAIBOT_DIR=/root/maibot-whale
MAIBOT_BIN=/root/.local/bin/maibot
MAIBOT_PORT=8001
CONFIG
    chmod 600 "$CONF"
  fi
  echo 'INSTALLED=YES'
}
mounted() { grep -q " $1 " /proc/mounts; }
prepare() {
  [ -x "$BB" ] || fail "缺少 KernelSU BusyBox：$BB"
  [ -x "$ROOTFS/bin/bash" ] || fail "Ubuntu chroot 不可访问：$ROOTFS"
  mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/proc" "$ROOTFS/sys"
  mounted "$ROOTFS/dev" || "$BB" mount --bind /dev "$ROOTFS/dev" || fail '挂载 /dev 失败'
  mounted "$ROOTFS/dev/pts" || "$BB" mount --bind /dev/pts "$ROOTFS/dev/pts" || fail '挂载 pts 失败'
  mounted "$ROOTFS/proc" || "$BB" mount --bind /proc "$ROOTFS/proc" || fail '挂载 proc 失败'
  mounted "$ROOTFS/sys" || "$BB" mount --bind /sys "$ROOTFS/sys" || fail '挂载 sys 失败'
}
ubuntu() {
  "$BB" chroot "$ROOTFS" /usr/bin/env -i HOME=/root \
    PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=xterm-256color /bin/bash -lc "$1"
}
probe() { ubuntu "curl -sS --max-time 3 -o /dev/null http://127.0.0.1:$1/" >/dev/null 2>&1; }
maibot_ok() { probe "$MAIBOT_PORT"; }
snow_ok() { probe 5099 || probe 3000; }
qq_ok() { ubuntu 'pgrep -f "^/opt/QQ/qq( |$)" >/dev/null' 2>/dev/null; }
stamp() { [ -r "/proc/$1/stat" ] && awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
owned() {
  [ -r "$STATE/maibot.pid" ] || return 1
  read -r pid token < "$STATE/maibot.pid" || return 1
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  [ -n "$token" ] && [ "$(stamp "$pid")" = "$token" ] && kill -0 "$pid" 2>/dev/null
}
legacy_active() {
  [ -e /data/adb/whale-controller/autoboot ] ||
  { [ -e /data/adb/whale-controller/wanted ] &&
    [ -e /data/adb/whale-controller/watch-enabled ]; }
}
launch_maibot() {
  maibot_ok && { echo 'MAIBOT=ALREADY_RUNNING'; return 0; }
  owned && { echo 'MAIBOT=OWNED_PROCESS_WAITING'; return 0; }
  # uv tool creates a symlink which may be absolute inside the guest.
  # A host-side -x on ROOTFS/path follows that link in Android's root namespace,
  # and can incorrectly report that the executable is missing.
  ubuntu "test -d '$MAIBOT_DIR'" || fail "Ubuntu 中找不到 MaiBot 目录：$MAIBOT_DIR"
  ubuntu "test -x '$MAIBOT_BIN'" || fail "Ubuntu 中无法执行 MaiBot：$MAIBOT_BIN"
  "$BB" nohup "$BB" chroot "$ROOTFS" /usr/bin/env -i HOME=/root \
    PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=xterm-256color /bin/bash -lc \
    "cd '$MAIBOT_DIR' && exec '$MAIBOT_BIN' run" \
    </dev/null >>"$STATE/maibot.log" 2>&1 &
  pid=$!
  sleep 1
  token=$(stamp "$pid")
  [ -n "$token" ] || fail "MaiBot 未能启动，查看 maibot.log"
  echo "$pid $token" > "$STATE/maibot.pid"
  echo 'MAIBOT=START_REQUESTED'
}
watch_alive() {
  [ -r "$STATE/watch.pid" ] || return 1
  read -r pid token < "$STATE/watch.pid" || return 1
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  [ -n "$token" ] && [ "$(stamp "$pid")" = "$token" ] && kill -0 "$pid" 2>/dev/null
}
watch_stop() {
  if watch_alive; then
    read -r pid token < "$STATE/watch.pid"
    kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -f "$STATE/watch.pid"
}
watch_start() {
  [ -e "$STATE/watch-enabled" ] || return 0
  watch_alive && return 0
  "$BB" nohup /system/bin/sh "$SELF" watch </dev/null >>"$STATE/watch.log" 2>&1 &
  pid=$!
  echo "$pid $(stamp "$pid")" > "$STATE/watch.pid"
}
start() {
  prepare
  legacy_active && fail '旧大肥鱼后台守护仍在启用，请先关闭旧守护，避免 QQAgent 被重新启动'
  touch "$STATE/wanted"
  # 复用现有 SnowLuma、Linux QQ，避免重复登录和连接冲突。
  if qq_ok; then
    echo 'QQ=EXISTING'
  elif [ -f "$ROOTFS/root/start-zhiy-qq.sh" ]; then
    ubuntu 'bash /root/start-zhiy-qq.sh' || echo 'WARN: QQ 启动脚本失败'
    echo 'QQ=START_REQUESTED'
  else
    echo 'QQ=NOT_RUNNING_NEEDS_SEPARATE_START'
  fi
  if snow_ok; then
    echo 'SNOWLUMA=EXISTING'
  elif [ -f "$ROOTFS/root/start-zhiy-snowluma.sh" ]; then
    ubuntu 'bash /root/start-zhiy-snowluma.sh' || echo 'WARN: SnowLuma 启动脚本失败'
    echo 'SNOWLUMA=START_REQUESTED'
  else
    echo 'SNOWLUMA=NOT_RUNNING_NEEDS_SEPARATE_START'
  fi
  launch_maibot
  watch_start
  echo 'START_COMMAND_COMPLETED=1'
}
stop() {
  rm -f "$STATE/wanted"
  watch_stop
  if owned; then
    read -r pid token < "$STATE/maibot.pid"
    kill -TERM "$pid" 2>/dev/null || true
    echo 'MAIBOT=STOP_REQUESTED'
  else
    echo 'MAIBOT=EXTERNAL_OR_NOT_RUNNING'
  fi
  rm -f "$STATE/maibot.pid"
  echo 'SNOWLUMA_AND_QQ=UNCHANGED'
  echo 'STOP_COMMAND_COMPLETED=1'
}
health() {
  prepare
  rc=0
  if maibot_ok; then echo 'MAIBOT=OK'; else echo 'MAIBOT=DOWN'; rc=1; fi
  if snow_ok; then echo 'SNOWLUMA=OK'; else echo 'SNOWLUMA=DOWN'; rc=1; fi
  if qq_ok; then echo 'QQ_PROCESS=OK'; else echo 'QQ_PROCESS=DOWN'; rc=1; fi
  if probe 6081; then echo 'VNC=OK'; else echo 'VNC=OPTIONAL_DOWN'; fi
  return "$rc"
}
status() {
  [ -e "$STATE/wanted" ] && echo 'WANTED=ON' || echo 'WANTED=OFF'
  [ -e "$STATE/watch-enabled" ] && echo 'WATCH=ON' || echo 'WATCH=OFF'
  watch_alive && echo 'WATCH_PROCESS=RUNNING' || echo 'WATCH_PROCESS=STOPPED'
  [ -e "$STATE/autoboot" ] && echo 'AUTOBOOT=ON' || echo 'AUTOBOOT=OFF'
  legacy_active && echo 'LEGACY_WATCH=ACTIVE' || echo 'LEGACY_WATCH=INACTIVE'
  echo "MAIBOT_DIR=$MAIBOT_DIR"
  health
}
watch() {
  trap 'exit 0' TERM INT
  misses=0
  while [ -e "$STATE/wanted" ] && [ -e "$STATE/watch-enabled" ]; do
    sleep 90 & wait $! || exit 0
    [ -e "$STATE/wanted" ] || break
    if maibot_ok; then misses=0; else
      misses=$((misses+1))
      echo "[$(date)] MaiBot health miss $misses/2"
      if [ "$misses" -ge 2 ]; then
        launch_maibot || true
        misses=0
      fi
    fi
  done
}
boot_write() {
  mkdir -p /data/adb/boot-completed.d
  if [ -e "$BOOTFILE" ] && ! grep -q '^# ZHIY_MANAGED$' "$BOOTFILE"; then
    fail '同名开机脚本不是本控制台创建，拒绝覆盖'
  fi
  cat > "$BOOTFILE" <<'BOOT'
#!/system/bin/sh
# ZHIY_MANAGED
S=/data/adb/zhiy-controller
[ -f "$S/autoboot" ] || exit 0
i=0
while [ ! -x /data/adb/ksu/bin/busybox ] || [ ! -x /data/local/chroot/ubuntu/bin/bash ]; do
  [ -f "$S/autoboot" ] || exit 0
  i=$((i+1))
  [ "$i" -lt 720 ] || exit 1
  sleep 5
done
exec /system/bin/sh "$S/controller.sh" start >>"$S/boot.log" 2>&1
BOOT
  chmod 700 "$BOOTFILE"
}
summary() {
  prepare
  ubuntu 'awk "/MemTotal:/ {total=int(\$2/1024)} /MemAvailable:/ {free=int(\$2/1024)} END {printf \"TOTAL_RAM_MB=%d\\nAVAILABLE_RAM_MB=%d\\n\",total,free}" /proc/meminfo'
  ubuntu 'df -h / | tail -n 1' | while IFS= read -r line; do echo "ROOTFS_DISK=$line"; done
}
action=status
[ "$#" -eq 0 ] || action=$1
case "$action" in
  install) install ;;
  start) start ;;
  stop) stop ;;
  status) status ;;
  watch) watch ;;
  watch-on) touch "$STATE/watch-enabled"; [ -e "$STATE/wanted" ] && watch_start; echo 'WATCH=ON' ;;
  watch-off) rm -f "$STATE/watch-enabled"; watch_stop; echo 'WATCH=OFF' ;;
  boot-on) boot_write; touch "$STATE/autoboot"; echo 'AUTOBOOT=ON' ;;
  boot-off)
    rm -f "$STATE/autoboot"
    if [ -e "$BOOTFILE" ] && grep -q '^# ZHIY_MANAGED$' "$BOOTFILE"; then rm -f "$BOOTFILE"; fi
    echo 'AUTOBOOT=OFF' ;;
  logs) tail -n 100 "$STATE/watch.log" 2>/dev/null || echo '暂无守护日志' ;;
  logs-boot) tail -n 100 "$STATE/boot.log" 2>/dev/null || echo '暂无开机日志' ;;
  logs-maibot) tail -n 100 "$STATE/maibot.log" 2>/dev/null || echo '暂无 MaiBot 日志' ;;
  summary) summary ;;
  *) fail "未知操作：$action" ;;
esac
