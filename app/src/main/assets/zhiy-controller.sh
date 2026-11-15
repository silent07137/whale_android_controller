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
  mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys"
  mounted "$ROOTFS/dev" || "$BB" mount --bind /dev "$ROOTFS/dev" || fail '挂载 /dev 失败'
  # Ubuntu chroot 必须拥有可用的私有 devpts。旧版直接 bind Android 的 /dev/pts，
  # Android 宿主可能没有此文件系统，结果 /dev/ptmx -> pts/ptmx 成为悬空链接。
  # 首先隔离 /dev bind 的 mount propagation，避免把 devpts 挂载传播回 Android 系统。
  "$BB" mount --make-rslave "$ROOTFS/dev" || fail '无法隔离 chroot /dev 的挂载传播'
  mkdir -p "$ROOTFS/dev/pts"
  # 不以 /proc/mounts 是否有条目作为 PTY 成功的证据；实际创建 PTY 才算通过。
  if ! "$BB" chroot "$ROOTFS" /usr/bin/python3 -c 'import pty,os; a,b=pty.openpty(); os.close(a); os.close(b)' >/dev/null 2>&1; then
    # 仅在没有 devpts 挂载时补挂；已有 devpts 仍失败则明确报错，不重复覆盖。
    if ! awk -v p="$ROOTFS/dev/pts" '$2==p && $3=="devpts" {found=1} END {exit !found}' /proc/mounts; then
      "$BB" mount -t devpts -o newinstance,ptmxmode=0666,mode=0620,gid=5 devpts "$ROOTFS/dev/pts" ||
        fail '挂载 Ubuntu 专用 devpts 失败'
    fi
    "$BB" chroot "$ROOTFS" /usr/bin/python3 -c 'import pty,os; a,b=pty.openpty(); os.close(a); os.close(b)' >/dev/null 2>&1 ||
      fail 'Ubuntu PTY 自检失败：请检查 /dev/ptmx 与 /dev/pts/ptmx'
  fi
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
port_open() { ubuntu "timeout 2 bash -c ':</dev/tcp/127.0.0.1/$1'" >/dev/null 2>&1; }
snow_ok() { port_open 5100; }
onebot_open() { port_open 3001; }
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
qq_guest() {
  # 原 QQAgentPlus 运行器的 QQ/VNC/SnowLuma 部分，不启动 QQAgentPlus 本体。
  ubuntu "export QQHOME='$QQ_PROFILE_HOME' ZHIY_ACTION='$1'
$(cat <<'GUEST'
set -u
umask 077
LAB=/root/qqagentplus-lab
SNL="$LAB/snowluma-new"
LOG="$LAB/logs"
RUNTIME=/root/.zhiy-runtime/derived-qq-stack
mkdir -p "$LOG" "$RUNTIME"
chmod 700 "$RUNTIME"
error() { echo "ERROR: $*" >&2; exit 1; }
tcp() { timeout 2 bash -c ":</dev/tcp/127.0.0.1/$1" >/dev/null 2>&1; }
env_has() { tr '\000' '\n' <"/proc/$1/environ" 2>/dev/null | grep -Fxq "$2"; }
find_owned() {
  local kind="$1" f pid cmd cwd
  for f in /proc/[0-9]*/cmdline; do
    pid="${f#/proc/}"; pid="${pid%/cmdline}"
    [ "$pid" != "$$" ] || continue
    cmd=$(cat "$f" 2>/dev/null | tr '\000' ' ') || continue
    [ -n "$cmd" ] || continue
    case "$kind" in
      snow) case "$cmd" in *index.mjs*|*launcher.sh*)
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
        [ "$cwd" = "$SNL" ] && echo "$pid";; esac ;;
      qq) case "$cmd" in *"/opt/QQ/qq"*)
        env_has "$pid" "HOME=$QQHOME" &&
        env_has "$pid" 'DISPLAY=:2' && echo "$pid";; esac ;;
      xvfb) case "$cmd" in *"Xvfb :2 "*) echo "$pid";; esac ;;
      flux) case "$cmd" in *fluxbox*)
        env_has "$pid" 'DISPLAY=:2' && echo "$pid";; esac ;;
      vnc) case "$cmd" in *x11vnc*"-rfbport 5902"*) echo "$pid";; esac ;;
      novnc) case "$cmd" in *websockify*"6082"*) echo "$pid";; esac ;;
    esac
  done
}
owned() { [ -n "$(find_owned "$1" | head -n 1)" ]; }
stamp() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null || true; }
remember() {
  local pid="$1" kind="$2" token
  token=$(stamp "$pid")
  [ -n "$token" ] && printf '%s %s\n' "$pid" "$token" >"$RUNTIME/$kind.pid"
}
launch() {
  nohup "$@" </dev/null >>"$LOG/$SERVICE.log" 2>&1 &
  local pid=$!
  remember "$pid" "$SERVICE"
  echo "$SERVICE=START_REQUESTED_PID_$pid"
}
start_qq() {
  [ -x /opt/QQ/qq ] || error '缺少 /opt/QQ/qq'
  [ -f "$SNL/launcher.sh" ] || error '缺少 SnowLuma launcher.sh'
  [ -d "$QQHOME/.config/QQ" ] || error "QQ 资料目录不存在：$QQHOME/.config/QQ"
  for pid in $(pgrep -f '^/opt/QQ/qq([[:space:]]|$)' 2>/dev/null || true); do
    if ! env_has "$pid" "HOME=$QQHOME" || ! env_has "$pid" 'DISPLAY=:2'; then
      error "发现其他 Linux QQ 账号实例（PID=$pid），请先正常退出"
    fi
  done
  if ! owned xvfb; then
    SERVICE=xvfb
    launch Xvfb :2 -screen 0 1280x800x24 -nolisten tcp
  fi
  sleep 2
  if ! owned flux; then
    SERVICE=flux
    DISPLAY=:2 HOME="$QQHOME" launch fluxbox
  fi
  if [ -s "$LAB/vnc.pass" ]; then
    if ! owned vnc; then
      SERVICE=vnc
      launch x11vnc -display :2 -localhost -rfbport 5902 \
        -rfbauth "$LAB/vnc.pass" -forever -shared -noshm
    fi
    if ! tcp 6082 && ! owned novnc; then
      SERVICE=novnc
      launch websockify --web=/usr/share/novnc 127.0.0.1:6082 127.0.0.1:5902
    fi
  else
    echo 'WARN=OLD_VNC_PASSWORD_FILE_MISSING'
  fi
  if ! owned qq; then
    mkdir -p "$QQHOME/.runtime"
    chmod 700 "$QQHOME" "$QQHOME/.runtime"
    SERVICE=qq
    HOME="$QQHOME" XDG_CONFIG_HOME="$QQHOME/.config" \
      XDG_CACHE_HOME="$QQHOME/.cache" XDG_DATA_HOME="$QQHOME/.local/share" \
      XDG_RUNTIME_DIR="$QQHOME/.runtime" DISPLAY=:2 \
      launch /opt/QQ/qq --no-sandbox --disable-gpu --disable-dev-shm-usage
  else
    echo 'QQ=ALREADY_RUNNING_WITH_OLD_PROFILE'
  fi
  # 若旧控制台启动的 SnowLuma 仍开启自动注入，不复用它进行知遥启动。
  for snow_pid in $(find_owned snow); do
    if env_has "$snow_pid" 'SNOWLUMA_HOOK_AUTOLOAD=1'; then
      error "检测到旧 SnowLuma 自动注入仍开启（PID=$snow_pid）；先正常停止该实例"
    fi
  done
  if ! tcp 5100 && ! owned snow; then
    (cd "$SNL" || exit 1
      SNOWLUMA_HOOK_AUTOLOAD=0 nohup ./launcher.sh \
        </dev/null >>"$LOG/snowluma.log" 2>&1 &
      pid=$!
      remember "$pid" snow
      echo "SNOWLUMA=START_REQUESTED_PID_$pid"
    )
  else
    echo 'SNOWLUMA=ALREADY_RUNNING_OR_PORT_OCCUPIED'
  fi
  sleep 3
  if tcp 6082; then echo 'NOVNC_6082=UP'; else echo 'NOVNC_6082=DOWN'; fi
  if owned qq; then echo 'QQ_PROCESS=UP'; else echo 'QQ_PROCESS=DOWN'; fi
  if tcp 5100; then echo 'SNOWLUMA_5100=UP'; else echo 'SNOWLUMA_5100=DOWN'; fi
  if tcp 3001; then echo 'ONEBOT_WS=LISTENING'; else echo 'ONEBOT_WS=DOWN'; fi
  echo 'ONEBOT_LOGIN=NOT_VERIFIED'
}
stop_qq() {
  local kind file pid token current cwd
  for kind in snow qq novnc vnc flux xvfb; do
    file="$RUNTIME/$kind.pid"
    [ -f "$file" ] || { echo "$kind=EXTERNAL_OR_NOT_OWNED"; continue; }
    read -r pid token <"$file" || true
    case "$pid" in ''|*[!0-9]*) rm -f "$file"; continue;; esac
    current=$(stamp "$pid")
    if [ -n "$token" ] && [ "$current" = "$token" ] &&
       kill -0 "$pid" 2>/dev/null; then
      case "$kind" in
        qq) env_has "$pid" "HOME=$QQHOME" &&
            env_has "$pid" 'DISPLAY=:2' || { echo 'qq=OTHER_PROFILE'; continue; } ;;
        snow) cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
          [ "$cwd" = "$SNL" ] || { echo 'snow=OTHER_DIRECTORY'; continue; } ;;
        *) ;;
      esac
      kill -TERM "$pid" 2>/dev/null || true
      echo "$kind=STOP_REQUESTED"
    else
      echo "$kind=STALE_OR_NOT_RUNNING"
    fi
    rm -f "$file"
  done
}
case "$ZHIY_ACTION" in
  start) start_qq ;;
  stop) stop_qq ;;
  *) error '未知 QQ 操作' ;;
esac
GUEST
)"
}
start_qq_stack() { qq_guest start; }
stop_qq_stack() { qq_guest stop; }

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
  if onebot_open; then echo 'ONEBOT_WS=LISTENING'; else echo 'ONEBOT_WS=DOWN'; fi
  echo 'ONEBOT_LOGIN=NOT_VERIFIED'
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
  if ubuntu 'python3 -c "import pty,os; a,b=pty.openpty(); os.close(a); os.close(b)"' >/dev/null 2>&1; then
    echo 'CHROOT_PTY=OK'
  else
    echo 'CHROOT_PTY=BROKEN'
  fi
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
    ubuntu 'echo "===== SnowLuma 原运行器日志 ====="; tail -n 65 /root/qqagentplus-lab/logs/snowluma.log 2>/dev/null || echo "尚无 SnowLuma 日志"; echo "===== SnowLuma 端口 ====="; ss -lnt 2>/dev/null | grep -E ":(5100|3001)[[:space:]]" || true' ;;
  logs-qq)
    prepare
    ubuntu 'echo "===== QQ 原运行器日志 ====="; tail -n 65 /root/qqagentplus-lab/logs/qq.log 2>/dev/null || echo "尚无 QQ 日志"; echo "===== QQ 进程 ====="; pgrep -af "/opt/QQ/qq" || true; echo "===== DISPLAY ====="; pgrep -af "Xvfb|fluxbox" || true' ;;
  logs-gui)
    prepare
    ubuntu 'echo "===== :2 / 5902 / 6082 ====="; ss -lntp 2>/dev/null | grep -E ":(5902|6082)[[:space:]]" || true; for n in xvfb fluxbox x11vnc novnc; do echo "===== $n ====="; tail -n 15 "/root/qqagentplus-lab/logs/$n.log" 2>/dev/null || true; done' ;;
  summary) summary ;;
  *) fail "未知操作：$action" ;;
esac
