#!/system/bin/sh
# 小鲸鱼控制台 KernelSU 控制层：与旧 whale-controller 完全分离
set -u
umask 077
STATE=/data/adb/qqaplus-controller
SELF="$STATE/controller.sh"
ROOTFS=/data/local/chroot/ubuntu
RUNNER=/root/qqagentplus-lab/control/runner.sh
BB=/data/adb/ksu/bin/busybox
BOOT=/data/adb/boot-completed.d/98-qqaplus-controller.sh
OLD_STATE=/data/adb/whale-controller
error() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || error 'KernelSU Root 未授权'
is_mounted() { grep -q " $1 " /proc/mounts; }
prepare() {
  [ -x "$BB" ] || error "无法使用 KernelSU BusyBox：$BB"
  [ -x "$ROOTFS/bin/bash" ] || error "找不到 Ubuntu：$ROOTFS"
  mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev/shm"
  is_mounted "$ROOTFS/dev" || "$BB" mount --bind /dev "$ROOTFS/dev" || error '挂载 /dev 失败'
  is_mounted "$ROOTFS/dev/pts" || "$BB" mount --bind /dev/pts "$ROOTFS/dev/pts" || error '挂载 /dev/pts 失败'
  is_mounted "$ROOTFS/proc" || "$BB" mount --bind /proc "$ROOTFS/proc" || error '挂载 /proc 失败'
  is_mounted "$ROOTFS/sys" || "$BB" mount --bind /sys "$ROOTFS/sys" || error '挂载 /sys 失败'
  mkdir -p "$ROOTFS/dev/shm"
  if ! is_mounted "$ROOTFS/dev/shm"; then
    "$BB" mount -t tmpfs -o size=256m,mode=1777,nosuid,nodev tmpfs "$ROOTFS/dev/shm" \
      || echo 'WARN: /dev/shm 挂载失败，QQ 使用 --disable-dev-shm-usage' >&2
  fi
}
ubuntu() {
  prepare
  [ -f "$ROOTFS$RUNNER" ] || error "缺少独立运行器：$RUNNER"
  "$BB" chroot "$ROOTFS" /usr/bin/env -i HOME=/root \
    PATH=/root/qqagentplus-lab/node-runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=xterm-256color /bin/bash "$RUNNER" "$1"
}
install() {
  [ -r "$2" ] || error '找不到安卓控制层源码'
  [ -r "$3" ] || error '找不到 Ubuntu 运行器源码'
  [ -x "$ROOTFS/bin/bash" ] || error 'Ubuntu chroot 尚未部署'
  mkdir -p "$STATE" "$ROOTFS/root/qqagentplus-lab/control"
  chmod 700 "$STATE" "$ROOTFS/root/qqagentplus-lab/control"
  cp "$2" "$SELF.new" || error '控制层复制失败'
  cp "$3" "$ROOTFS$RUNNER.new" || error 'Ubuntu 运行器复制失败'
  chmod 700 "$SELF.new" "$ROOTFS$RUNNER.new"
  mv -f "$SELF.new" "$SELF"
  mv -f "$ROOTFS$RUNNER.new" "$ROOTFS$RUNNER"
  echo 'INSTALLED=YES'
}
watch_pid() {
  [ -f "$STATE/watch.pid" ] || return 1
  p=$(cat "$STATE/watch.pid" 2>/dev/null) || return 1
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$p/cmdline" ] || return 1
  tr '\000' ' ' < "/proc/$p/cmdline" | grep -Fq "$SELF watch"
}
stop_watch() {
  if watch_pid; then kill -TERM "$(cat "$STATE/watch.pid")" 2>/dev/null || true; fi
  rm -f "$STATE/watch.pid"
}
spawn_watch() {
  [ -f "$STATE/wanted" ] && [ -f "$STATE/watch-enabled" ] || return 0
  watch_pid && return 0
  "$BB" nohup /system/bin/sh "$SELF" watch </dev/null >>"$STATE/watch.log" 2>&1 &
  echo "$!" > "$STATE/watch.pid"
}
start() {
  # 不覆盖已有启动参数/记忆，重复点击只补齐缺失进程
  touch "$STATE/wanted"
  ubuntu start
  spawn_watch
}
stop_all() {
  rm -f "$STATE/wanted"
  stop_watch
  ubuntu stop
}
status() {
  if [ -f "$STATE/wanted" ]; then echo 'WANTED=ON'; else echo 'WANTED=OFF'; fi
  if [ -f "$STATE/watch-enabled" ]; then echo 'WATCH=ON'; else echo 'WATCH=OFF'; fi
  if watch_pid; then echo 'WATCH_PROCESS=RUNNING'; else echo 'WATCH_PROCESS=STOPPED'; fi
  if [ -f "$STATE/autoboot" ]; then echo 'AUTOBOOT=ON'; else echo 'AUTOBOOT=OFF'; fi
  if [ -f "$OLD_STATE/autoboot" ]; then
    echo 'OLD_CONTROLLER_AUTOBOOT=ON'
    echo 'WARN: 旧鲸鱼控制台开机自启仍启用；请先手动关闭旧控制台的自启'
  else
    echo 'OLD_CONTROLLER_AUTOBOOT=OFF'
  fi
  ubuntu status
}
watch() {
  trap 'exit 0' TERM INT
  failed=0
  repairs=0
  echo "[$(date)] 守护启动"
  while [ -f "$STATE/wanted" ] && [ -f "$STATE/watch-enabled" ]; do
    sleep 120 & wait $! || exit 0
    [ -f "$STATE/wanted" ] && [ -f "$STATE/watch-enabled" ] || break
    if ubuntu health >/dev/null 2>&1; then
      failed=0
    else
      failed=$((failed + 1))
      echo "[$(date)] 服务健康检测失败 $failed/2"
      if [ "$failed" -ge 2 ]; then
        repairs=$((repairs + 1))
        if [ "$repairs" -gt 3 ]; then
          echo "[$(date)] 已达到最多 3 次恢复，停止守护避免无限重启"
          break
        fi
        echo "[$(date)] 正在尝试恢复缺失的进程"
        ubuntu start >>"$STATE/watch.log" 2>&1 || true
        failed=0
      fi
    fi
  done
  echo "[$(date)] 守护结束"
}
write_boot() {
  [ ! -f "$OLD_STATE/autoboot" ] || error '旧控制台仍启用开机自启；请先关闭旧控制台开机自启'
  mkdir -p /data/adb/boot-completed.d
  if [ -f "$BOOT" ] && ! grep -q '^# QQAPLUS_CONTROLLER_MANAGED$' "$BOOT"; then
    error "拒绝覆盖其他程序的开机脚本：$BOOT"
  fi
  cat >"$BOOT" <<'BOOT_SCRIPT'
#!/system/bin/sh
# QQAPLUS_CONTROLLER_MANAGED
BASE=/data/adb/qqaplus-controller
[ -f "$BASE/autoboot" ] || exit 0
# 某些设备开机解锁前无法访问 chroot；最多等待 30 分钟
i=0
while [ ! -x /data/local/chroot/ubuntu/bin/bash ] || [ ! -x /data/adb/ksu/bin/busybox ]; do
  [ -f "$BASE/autoboot" ] || exit 0
  i=$((i + 1))
  [ "$i" -lt 360 ] || exit 1
  sleep 5
done
[ -f "$BASE/autoboot" ] || exit 0
exec /system/bin/sh "$BASE/controller.sh" start >>"$BASE/boot.log" 2>&1
BOOT_SCRIPT
  chmod 700 "$BOOT"
}
mkdir -p "$STATE"
case "$1" in
  install) install "$@" ;;
  start) start ;;
  stop) stop_all ;;
  status) status ;;
  watch) watch ;;
  watch-on) touch "$STATE/watch-enabled"; spawn_watch; echo 'WATCH=ON' ;;
  watch-off) rm -f "$STATE/watch-enabled"; stop_watch; echo 'WATCH=OFF' ;;
  boot-on) write_boot; touch "$STATE/autoboot"; echo 'AUTOBOOT=ON' ;;
  boot-off)
    rm -f "$STATE/autoboot"
    if [ -f "$BOOT" ] && grep -q '^# QQAPLUS_CONTROLLER_MANAGED$' "$BOOT"; then rm -f "$BOOT"; fi
    echo 'AUTOBOOT=OFF' ;;
  log-agent|log-snow|log-qq|log-vnc) ubuntu "$1" ;;
  log-watch) tail -n 55 "$STATE/watch.log" 2>/dev/null || true ;;
  log-boot) tail -n 50 "$STATE/boot.log" 2>/dev/null || true ;;
  *) error '支持 install/start/stop/status/watch-on/watch-off/boot-on/boot-off/log-*' ;;
esac
