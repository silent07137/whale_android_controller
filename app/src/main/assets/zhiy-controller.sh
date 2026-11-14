#!/system/bin/sh
# 知遥控制台，独立于 Termux。管理 MaiBot、SnowLuma、Linux QQ 和图形层；绝不启动 QQAgent。
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
# 已确认旧 Linux QQ 专用资料目录；若目标账号不同，仅修改 Root 私有 config.sh。
QQ_PROFILE_HOME=/root/qqagentplus-lab/qq-home
# 仅在 Root 私有文件内自定义，不能填写 QQAgent 旧启动脚本。
[ -f "$CONF" ] && . "$CONF"
# 防止将配置路径插入 Shell 命令；不能将 HOME 重设为 /root。
case "$QQ_PROFILE_HOME" in
  /root/*) case "$QQ_PROFILE_HOME" in *[!A-Za-z0-9_./-]*) fail 'QQ_PROFILE_HOME 含非法字符';; esac ;;
  *) fail 'QQ_PROFILE_HOME 必须是 Ubuntu 内已有的 /root/ 子目录' ;;
esac
[ "$QQ_PROFILE_HOME" != /root ] || fail '拒绝以 /root 默认资料目录启动 QQ'
install() {
  cp "$0" "$SELF.new" && chmod 700 "$SELF.new" && mv -f "$SELF.new" "$SELF" || fail '安装失败'
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<'CONFIG'
MAIBOT_DIR=/root/maibot-whale
MAIBOT_BIN=/root/.local/bin/maibot
MAIBOT_PORT=8001
# QQ_PROFILE_HOME is the dedicated existing QQ login profile, never /root.
QQ_PROFILE_HOME=/root/qqagentplus-lab/qq-home
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
qq_ok() {
  ubuntu "EXPECTED_HOME='$QQ_PROFILE_HOME'
EXPECTED_DISPLAY=':2'
for pid in \$(pgrep -f '^/opt/QQ/qq([[:space:]]|$)' 2>/dev/null || true); do
  [ -r \"/proc/\$pid/environ\" ] || continue
  if tr '\\0' '\\n' <\"/proc/\$pid/environ\" | grep -Fx \"HOME=\$EXPECTED_HOME\" >/dev/null &&
     tr '\\0' '\\n' <\"/proc/\$pid/environ\" | grep -Fx \"DISPLAY=\$EXPECTED_DISPLAY\" >/dev/null; then
    exit 0
  fi
done
exit 1" 2>/dev/null
}
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
stop_qq_stack() {
  # 只停止由知遥启动器启动并记录 PID 与进程开始时间的进程。
  ubuntu "$(cat <<'GUEST'
for key in qq snow; do
  file="/root/.zhiy-runtime/$key.pid"
  [ -f "$file" ] || { echo "$key=EXTERNAL_OR_STOPPED"; continue; }
  read -r pid stamp < "$file" || true
  case "$pid" in ''|*[!0-9]*) rm -f "$file"; continue;; esac
  if [ -n "$stamp" ] && [ -r "/proc/$pid/stat" ] &&
     [ "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$stamp" ]; then
    # 新版不能误停旧版 v0.1.5 启动的 DISPLAY=:1 QQ 或 SnowLuma。
    if [ "$key" = qq ] || [ "$key" = snow ]; then
      if ! tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -Fx 'DISPLAY=:2' >/dev/null; then
        echo "$key=SKIPPED_OTHER_DISPLAY"
        rm -f "$file"
        continue
      fi
    fi
    kill -TERM "$pid" 2>/dev/null || true
    echo "$key=STOP_REQUESTED"
  else echo "$key=NOT_OWNED"; fi
  rm -f "$file"
done
GUEST
)"
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
start_qq_stack() {
  # 严禁隐式创建新 QQ 账号资料目录：只接受已存在的独立登录资料。
  ubuntu "test -d '$QQ_PROFILE_HOME/.config/QQ'" || {
    echo "ERROR=QQ_PROFILE_DATA_MISSING:$QQ_PROFILE_HOME/.config/QQ"
    return 13
  }
  ubuntu "export QQ_PROFILE_HOME='$QQ_PROFILE_HOME'
$(cat <<'GUEST'
set -u
qq_failed=0
export DISPLAY=:2
mkdir -p /root/.vnc /root/.zhiy-runtime /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
# 在启动 SnowLuma/QQ 前检查所有已运行的 QQ，防止误用别人的 QQ 登录资料。
for running_pid in $(pgrep -f "^/opt/QQ/qq([[:space:]]|$)" 2>/dev/null || true); do
  if [ -r "/proc/$running_pid/environ" ] &&
    tr '\0' '\n' <"/proc/$running_pid/environ" |
      grep -Fx "HOME=$QQ_PROFILE_HOME" >/dev/null &&
    tr '\0' '\n' <"/proc/$running_pid/environ" |
      grep -Fx 'DISPLAY=:2' >/dev/null; then
    :
  else
    echo "ERROR=QQ_WRONG_PROFILE_ALREADY_RUNNING"
    exit 14
  fi
done
xvfb_2_running() {
  for pid in $(pgrep -x Xvfb 2>/dev/null || true); do
    [ -r "/proc/$pid/cmdline" ] || continue
    if tr '\0' ' ' <"/proc/$pid/cmdline" |
       grep -Eq '(^|[[:space:]])Xvfb[[:space:]]+:2([[:space:]]|$)'; then return 0; fi
  done
  return 1
}
if ! xvfb_2_running; then
  if command -v Xvfb >/dev/null; then
    nohup Xvfb :2 -screen 0 1280x800x24 -nolisten tcp >/tmp/zhiy-xvfb.log 2>&1 &
    echo "XVFB=START_REQUESTED"
  else echo "WARN=Xvfb_not_installed"; fi
fi
sleep 2
fluxbox_2_running() {
  for pid in $(pgrep -x fluxbox 2>/dev/null || true); do
    if [ -r "/proc/$pid/environ" ] &&
       tr '\0' '\n' <"/proc/$pid/environ" | grep -Fx 'DISPLAY=:2' >/dev/null; then return 0; fi
  done
  return 1
}
if ! fluxbox_2_running; then
  if command -v fluxbox >/dev/null; then
    nohup fluxbox >/tmp/zhiy-fluxbox.log 2>&1 &
    echo "FLUXBOX=START_REQUESTED"
  else echo "WARN=fluxbox_not_installed"; fi
fi
if ! ss -lnt 2>/dev/null | grep -Eq ':5902[[:space:]]'; then
  if command -v x11vnc >/dev/null; then
    # 还原用户原本的回环地址 VNC 会话：:2 / 5902 / 6082。
    # 仅监听 localhost，避免无密码 VNC 暴露到局域网。
    nohup x11vnc -display :2 -noshm -noxdamage -localhost -rfbport 5902 \
      -nopw -forever -shared >/tmp/zhiy-x11vnc.log 2>&1 &
    echo "VNC_5902=START_REQUESTED"
  else echo "WARN=x11vnc_not_installed"; fi
fi
if ! curl -sS -o /dev/null --max-time 2 http://127.0.0.1:6082/vnc.html; then
  if command -v websockify >/dev/null && [ -d /usr/share/novnc ]; then
    nohup websockify --web=/usr/share/novnc 127.0.0.1:6082 127.0.0.1:5902 \
      >/tmp/zhiy-websockify.log 2>&1 &
    echo "NOVNC=START_REQUESTED"
  else echo "WARN=websockify_or_noVNC_missing"; fi
fi
snow_up() {
  curl -sS -o /dev/null --max-time 2 http://127.0.0.1:5099/ 2>/dev/null ||
  curl -sS -o /dev/null --max-time 2 http://127.0.0.1:3000/ 2>/dev/null
}
if snow_up; then
  echo "SNOWLUMA=ALREADY_RUNNING"
else
  SNOW_DIR=
  for candidate in /root/qqagentplus-lab/snowluma-new /opt/whale/snowluma; do
    if [ -f "$candidate/index.mjs" ]; then SNOW_DIR="$candidate"; break; fi
    candidate_entry=$(find "$candidate" -maxdepth 3 -type f -name index.mjs \
      -not -path "*/node_modules/*" -print -quit 2>/dev/null)
    if [ -n "$candidate_entry" ]; then
      SNOW_DIR=$(dirname "$candidate_entry")
      break
    fi
  done
  if [ -z "$SNOW_DIR" ]; then
    echo "WARN=SnowLuma_entry_not_found"
  else
    if [ -f /root/.zhiy-runtime/snow.pid ]; then
      read -r snow_pid snow_stamp < /root/.zhiy-runtime/snow.pid || true
      if [ -n "$snow_pid" ] && [ -n "$snow_stamp" ] &&
         [ -r "/proc/$snow_pid/stat" ] &&
         [ "$(awk '{print $22}' "/proc/$snow_pid/stat")" = "$snow_stamp" ] &&
         kill -0 "$snow_pid" 2>/dev/null; then
        echo "SNOWLUMA=STARTING"
      else
        rm -f /root/.zhiy-runtime/snow.pid
      fi
    fi
    if [ ! -f /root/.zhiy-runtime/snow.pid ]; then
      ( cd "$SNOW_DIR" || exit 1
        nohup env DISPLAY=:2 SNOWLUMA_HOOK_AUTOLOAD=1 node ./index.mjs \
          >/tmp/zhiy-snowluma.log 2>&1 &
        pid=$!
        stamp=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)
        if [ -n "$stamp" ]; then
          echo "$pid $stamp" > /root/.zhiy-runtime/snow.pid
          echo "SNOWLUMA=START_REQUESTED"
        else
          echo "WARN=SnowLuma_exited_early"
        fi
      )
    fi
  fi
fi
# Hook 必须在 QQ 冷启动前就绪，避免 QQ 先运行但未被注入。
ready=0
for try in 1 2 3 4 5 6 7 8 9 10; do
  if snow_up; then ready=1; break; fi
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "ERROR=SNOWLUMA_NOT_READY_CHECK_ZHIY_SNOWLUMA_LOG"
  # 不启动未注入 Hook 的 QQ；如 QQ 已经独立运行，也不要杀掉它。
  exit 11
fi
sleep 1
# 当前运行的 QQ 即使来自同一个可执行文件，也可能使用其他账号。
# 为避免两个账号争抢 Hook，遇到不匹配的进程则停止继续启动，而非复用它。
qq_pids=$(pgrep -f "^/opt/QQ/qq([[:space:]]|$)" 2>/dev/null || true)
if [ -n "$qq_pids" ]; then
  matched=0
  for running_pid in $qq_pids; do
    if [ -r "/proc/$running_pid/environ" ] &&
      tr '\0' '\n' < "/proc/$running_pid/environ" | grep -Fx "HOME=$QQ_PROFILE_HOME" >/dev/null &&
      tr '\0' '\n' < "/proc/$running_pid/environ" | grep -Fx 'DISPLAY=:2' >/dev/null; then
      matched=1
      break
    fi
  done
  if [ "$matched" = 1 ]; then
    echo "QQ=ALREADY_RUNNING_WITH_EXPECTED_PROFILE"
  else
    echo "ERROR=QQ_WRONG_PROFILE_ALREADY_RUNNING"
    exit 14
  fi
elif [ -x /opt/QQ/qq ]; then
  echo "QQ_PROFILE_HOME=$QQ_PROFILE_HOME"
  mkdir -p "$QQ_PROFILE_HOME/.runtime"
  chmod 700 "$QQ_PROFILE_HOME/.runtime"
  nohup env DISPLAY=:2 HOME="$QQ_PROFILE_HOME" \
    XDG_CONFIG_HOME="$QQ_PROFILE_HOME/.config" \
    XDG_DATA_HOME="$QQ_PROFILE_HOME/.local/share" \
    XDG_CACHE_HOME="$QQ_PROFILE_HOME/.cache" \
    XDG_RUNTIME_DIR="$QQ_PROFILE_HOME/.runtime" \
    /opt/QQ/qq --user-data-dir="$QQ_PROFILE_HOME/.config/QQ" --no-sandbox --disable-gpu --disable-dev-shm-usage \
    >/tmp/zhiy-linuxqq.log 2>&1 &
  qq_pid=$!
  qq_stamp=$(awk '{print $22}' "/proc/$qq_pid/stat" 2>/dev/null || true)
  if [ -n "$qq_stamp" ]; then
    echo "$qq_pid $qq_stamp" >/root/.zhiy-runtime/qq.pid
  fi
  echo "QQ=LAUNCH_SENT_WITH_DEDICATED_PROFILE"
  sleep 6
  if [ -r "/proc/$qq_pid/environ" ] &&
     tr '\0' '\n' <"/proc/$qq_pid/environ" | grep -Fx "HOME=$QQ_PROFILE_HOME" >/dev/null &&
     tr '\0' '\n' <"/proc/$qq_pid/environ" | grep -Fx 'DISPLAY=:2' >/dev/null; then
    echo "QQ=EXPECTED_PROFILE_PROCESS_RUNNING"
  else
    echo "ERROR=QQ_EXITED_CHECK_ZHIY_LINUXQQ_LOG"
    qq_failed=1
  fi
else
  echo "ERROR=QQ_BINARY_MISSING"
  qq_failed=1
fi
# 必须同时有 noVNC 网页与 VNC 后端，否则明确报错。
vnc_ready=0
for try in 1 2 3 4 5; do
  if curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:6082/vnc.html &&
     ss -lnt 2>/dev/null | grep -Eq ':5902[[:space:]]'; then
    vnc_ready=1
    break
  fi
  sleep 1
done
if [ "$vnc_ready" != 1 ]; then
  echo "ERROR=NOVNC_6082_OR_VNC_5902_NOT_READY"
  qq_failed=1
fi
if [ "$qq_failed" = 1 ]; then exit 10; fi
GUEST
)"
}

start() {
  prepare
  legacy_active && fail '旧大肥鱼后台守护仍在启用，请先关闭旧守护，避免 QQAgent 被重新启动'
  touch "$STATE/wanted"
  # 即使 QQ 链路失败，MaiBot 仍可用于 WebUI 排错，但必须报告部分失败。
  stack_rc=0
  start_qq_stack || stack_rc=$?
  launch_maibot
  watch_start
  if [ "$stack_rc" -ne 0 ]; then
    echo "START_PARTIAL_FAILURE=QQ_STACK_EXIT_$stack_rc"
    echo 'HINT=SEE_LOGS_SNOW_AND_LOGS_QQ'
    return 1
  fi
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
  prepare
  stop_qq_stack || echo 'WARN=QQ_STACK_STOP_PARTIAL'
  echo 'STOP_COMMAND_COMPLETED=1'
}
health() {
  prepare
  rc=0
  if maibot_ok; then echo 'MAIBOT=OK'; else echo 'MAIBOT=DOWN'; rc=1; fi
  if snow_ok; then echo 'SNOWLUMA=OK'; else echo 'SNOWLUMA=DOWN'; rc=1; fi
  if qq_ok; then
    echo 'QQ_PROCESS=OK'
  elif ubuntu 'pgrep -f "^/opt/QQ/qq([[:space:]]|$)" >/dev/null' 2>/dev/null; then
    echo 'QQ_PROCESS=WRONG_PROFILE'
    rc=1
  else
    echo 'QQ_PROCESS=DOWN'
    rc=1
  fi
  # noVNC 6082 必须同时具有对应的 x11vnc 5902 后端。
  if ubuntu 'curl -fsS -o /dev/null --max-time 3 http://127.0.0.1:6082/vnc.html && ss -lnt | grep -Eq ":5902[[:space:]]"'; then
    echo 'VNC=OK'
  else
    echo 'VNC=BACKEND_DOWN_OR_WEB_DOWN'
    rc=1
  fi
  return "$rc"
}
status() {
  [ -e "$STATE/wanted" ] && echo 'WANTED=ON' || echo 'WANTED=OFF'
  [ -e "$STATE/watch-enabled" ] && echo 'WATCH=ON' || echo 'WATCH=OFF'
  watch_alive && echo 'WATCH_PROCESS=RUNNING' || echo 'WATCH_PROCESS=STOPPED'
  [ -e "$STATE/autoboot" ] && echo 'AUTOBOOT=ON' || echo 'AUTOBOOT=OFF'
  legacy_active && echo 'LEGACY_WATCH=ACTIVE' || echo 'LEGACY_WATCH=INACTIVE'
  echo "MAIBOT_DIR=$MAIBOT_DIR"
  echo "QQ_PROFILE_HOME=$QQ_PROFILE_HOME"
  echo 'QQ_DISPLAY=:2'
  echo 'QQ_VNC_BACKEND=5902'
  echo 'QQ_NOVNC=6082'
  health
}
watch() {
  trap 'exit 0' TERM INT
  misses=0
  while [ -e "$STATE/wanted" ] && [ -e "$STATE/watch-enabled" ]; do
    sleep 90 & wait $! || exit 0
    [ -e "$STATE/wanted" ] || break
    if health >/dev/null 2>&1; then misses=0; else
      misses=$((misses+1))
      echo "[$(date)] MaiBot health miss $misses/2"
      if [ "$misses" -ge 2 ]; then
        start || true
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
  logs-snow)
    prepare
    ubuntu 'echo "===== SnowLuma 启动日志 ====="; tail -n 65 /tmp/zhiy-snowluma.log 2>/dev/null || echo "尚无 SnowLuma 日志"; echo "===== SnowLuma 端口 ====="; ss -lnt 2>/dev/null | grep -E ":(5099|3000|3001)[[:space:]]" || true' ;;
  logs-qq)
    prepare
    ubuntu 'echo "===== QQ 启动日志 ====="; tail -n 65 /tmp/zhiy-linuxqq.log 2>/dev/null || echo "尚无 QQ 启动日志"; echo "===== QQ 进程 ====="; pgrep -af "/opt/QQ/qq" || true; echo "===== DISPLAY ====="; pgrep -af "Xvfb|fluxbox" || true' ;;
  logs-gui)
    prepare
    ubuntu 'echo "===== :2 / 5902 / 6082 ====="; ss -lntp 2>/dev/null | grep -E ":(5902|6082)[[:space:]]" || true; for n in xvfb fluxbox x11vnc websockify; do echo "===== $n ====="; tail -n 15 "/tmp/zhiy-$n.log" 2>/dev/null || true; done' ;;
  summary) summary ;;
  *) fail "未知操作：$action" ;;
esac
