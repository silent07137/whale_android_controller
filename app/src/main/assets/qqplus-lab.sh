#!/bin/bash
# QQAgentPlus 独立服务：仅管理 /root/qqagentplus-lab
set -u
umask 077
LAB=/root/qqagentplus-lab
SNL="$LAB/snowluma-new"
QQHOME="$LAB/qq-home"
LOG="$LAB/logs"
mkdir -p "$LOG" "$QQHOME/.config" "$QQHOME/.cache" "$QQHOME/.local/share" "$QQHOME/.runtime"
chmod 700 "$QQHOME" "$QQHOME/.runtime"
error() { echo "ERROR: $*" >&2; exit 1; }
tcp() { timeout 2 bash -c ":</dev/tcp/127.0.0.1/$1" >/dev/null 2>&1; }
env_has() { cat "/proc/$1/environ" 2>/dev/null | tr '\000' '\n' | grep -Fxq "$2"; }
find_owned() {
  local kind="$1" f pid cmd cwd
  for f in /proc/[0-9]*/cmdline; do
    pid="${f#/proc/}"; pid="${pid%/cmdline}"
    [ "$pid" != "$$" ] || continue
    # /proc 中的进程可能恰好退出：将读取错误静默处理，不作为服务故障。
    cmd=$(cat "$f" 2>/dev/null | tr '\000' ' ') || continue
    [ -n "$cmd" ] || continue
    case "$kind" in
      agent) case "$cmd" in *src/server.js*) env_has "$pid" "QQ_AGENT_DATA_DIR=$LAB/data" && echo "$pid";; esac ;;
      snow) case "$cmd" in *index.mjs*|*launcher.sh*)
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
        case "$cwd" in *"$SNL") echo "$pid";; esac ;;
      esac ;;
      qq) case "$cmd" in *"/opt/QQ/qq"*) env_has "$pid" "HOME=$QQHOME" && echo "$pid";; esac ;;
      xvfb) case "$cmd" in *"Xvfb :2 "*) echo "$pid";; esac ;;
      flux) case "$cmd" in *fluxbox*) env_has "$pid" 'DISPLAY=:2' && echo "$pid";; esac ;;
      vnc) case "$cmd" in *x11vnc*"-rfbport 5902"*) echo "$pid";; esac ;;
      novnc) case "$cmd" in *websockify*"6082"*) echo "$pid";; esac ;;
    esac
  done
}
owned() { [ -n "$(find_owned "$1" | head -n 1)" ]; }
launch() {
  nohup "$@" </dev/null >>"$LOG/$SERVICE.log" 2>&1 &
  echo "$SERVICE PID=$!"
}
status() {
  if tcp 43210; then echo 'AGENT=UP'; else echo 'AGENT=DOWN'; fi
  if tcp 5100; then echo 'SNOWLUMA=UP'; else echo 'SNOWLUMA=DOWN'; fi
  if tcp 3001; then echo 'ONEBOT_WS=LISTENING'; else echo 'ONEBOT_WS=DOWN'; fi
  if owned qq; then echo 'QQ_PROCESS=UP'; else echo 'QQ_PROCESS=DOWN'; fi
  if owned xvfb; then echo 'DESKTOP=UP'; else echo 'DESKTOP=DOWN'; fi
  if tcp 6082; then echo 'NOVNC=UP'; else echo 'NOVNC=DOWN'; fi
  echo 'ONEBOT_LOGIN=NOT_VERIFIED'
  echo 'NOTE=端口监听不等于收发正常，请在控制台测试消息'
}
start() {
  [ -x /opt/QQ/qq ] || error '缺少 /opt/QQ/qq'
  [ -f "$SNL/launcher.sh" ] || error '缺少独立 SnowLuma'
  [ -f "$LAB/app/src/server.js" ] || error '缺少 QQAgentPlus'
  if ! owned xvfb; then
    SERVICE=xvfb
    launch Xvfb :2 -screen 0 1280x800x24 -nolisten tcp
  fi
  sleep 2
  if ! owned flux; then
    SERVICE=fluxbox
    DISPLAY=:2 HOME="$QQHOME" launch fluxbox
  fi
  if [ -s "$LAB/vnc.pass" ]; then
    if ! owned vnc; then
      SERVICE=x11vnc
      launch x11vnc -display :2 -localhost -rfbport 5902 \
        -rfbauth "$LAB/vnc.pass" -forever -shared -noshm
    fi
    if ! tcp 6082 && ! owned novnc; then
      SERVICE=novnc
      launch websockify --web=/usr/share/novnc 127.0.0.1:6082 127.0.0.1:5902
    fi
  else
    echo 'WARN: 没找到 VNC 密码文件，跳过图形远程访问'
  fi
  if ! owned qq; then
    SERVICE=qq
    HOME="$QQHOME" XDG_CONFIG_HOME="$QQHOME/.config" \
      XDG_CACHE_HOME="$QQHOME/.cache" XDG_DATA_HOME="$QQHOME/.local/share" \
      XDG_RUNTIME_DIR="$QQHOME/.runtime" DISPLAY=:2 \
      launch /opt/QQ/qq --no-sandbox --disable-gpu --disable-dev-shm-usage
  fi
  if ! tcp 5100 && ! owned snow; then
    (cd "$SNL" && SNOWLUMA_HOOK_AUTOLOAD=0 \
      nohup ./launcher.sh </dev/null >>"$LOG/snowluma.log" 2>&1 &)
    echo 'SnowLuma 已请求启动（保留手动注入）'
  fi
  NODE="$LAB/node-runtime/bin/node"
  [ -x "$NODE" ] || NODE="$(command -v node || true)"
  [ -n "$NODE" ] || error '找不到 Ubuntu Node.js'
  if ! tcp 43210 && ! owned agent; then
    (cd "$LAB/app" && QQ_AGENT_DATA_DIR="$LAB/data" QQ_AGENT_RUNTIME=container \
      QQ_AGENT_SERVER_HOST=127.0.0.1 QQ_AGENT_SERVER_PORT=43210 \
      QQ_AGENT_ONEBOT_HTTP_URL=http://127.0.0.1:3000 \
      QQ_AGENT_ONEBOT_WS_URL=ws://127.0.0.1:3001 \
      nohup "$NODE" src/server.js </dev/null >>"$LOG/qqagentplus.log" 2>&1 &)
    echo 'QQAgentPlus 已请求启动（保留已有运行模式）'
  fi
  sleep 3
  status
}
terminate_owned() {
  local kind="$1" p
  for p in $(find_owned "$kind" | sort -nr); do
    echo "停止 $kind PID=$p"
    kill -TERM "$p" 2>/dev/null || true
  done
}
stop() {
  terminate_owned agent
  terminate_owned snow
  terminate_owned qq
  terminate_owned novnc
  terminate_owned vnc
  terminate_owned flux
  terminate_owned xvfb
  echo '已发送停止信号；未删除账号、记忆或配置'
  sleep 2
  status
}
health() { tcp 43210 && tcp 5100 && owned qq; }
case "$*" in
  start) start ;;
  stop) stop ;;
  status|'') status ;;
  health) health ;;
  log-agent) tail -n 60 "$LOG/qqagentplus.log" 2>/dev/null || true ;;
  log-snow) tail -n 60 "$LOG/snowluma.log" 2>/dev/null || true ;;
  log-qq) tail -n 60 "$LOG/qq.log" 2>/dev/null || true ;;
  log-vnc) tail -n 40 "$LOG/x11vnc.log" 2>/dev/null || true ;;
  *) error '未知操作' ;;
esac
