#!/bin/sh
# Desktop inside the embedded Alpine system. The panel port is already public.
set -eu
unset WAYLAND_DISPLAY WAYLAND_SOCKET || true

# Resolve rootfs base when running directly in /home/container without chroot/proot
BASE_DIR="/home/container"
if [ ! -d "${BASE_DIR}" ]; then
    BASE_DIR="$(pwd)"
fi

ROOT_HOME="${BASE_DIR}/root"
LOG_DIR="${BASE_DIR}/var/log"
TMP_DIR="${BASE_DIR}/tmp"
X11_DIR="${TMP_DIR}/.X11-unix"

mkdir -p "${ROOT_HOME}" "${LOG_DIR}" "${X11_DIR}" 2>/dev/null || true

export HOME="${ROOT_HOME}"
export TMPDIR="${TMP_DIR}"
export DISPLAY=:1
export XDG_SESSION_TYPE=x11
export PATH="${BASE_DIR}/usr/local/sbin:${BASE_DIR}/usr/local/bin:${BASE_DIR}/usr/sbin:${BASE_DIR}/usr/bin:${BASE_DIR}/sbin:${BASE_DIR}/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

if [ -x "${BASE_DIR}/bin/bash" ]; then
    export SHELL="${BASE_DIR}/bin/bash"
elif [ -x "/bin/bash" ]; then
    export SHELL="/bin/bash"
else
    export SHELL="/bin/sh"
fi

cd "${ROOT_HOME}" || cd "${BASE_DIR}"

GEOMETRY="${VNC_GEOMETRY:-1280x720x24}"
PORT="${SERVER_PORT:-25628}"
# Classic VNC keeps 8 characters. x11vnc -storepasswd writes a binary blob, and
# -passwdfile on this build reads a text line (fgets). A blob with a NUL or
# newline makes x11vnc exit, and a blob without one is not the typed password.
PASS=$(printf '%s' "${VNC_PASSWORD:-pterovm}" | tr -d '\r\n')
PASS=$(printf '%.8s' "$PASS")
if [ -z "$PASS" ]; then
    PASS=pterovm
fi

umask 077
printf '%s\n' "$PASS" > "${ROOT_HOME}/vnc.pass"
chmod 600 "${ROOT_HOME}/vnc.pass"

# Xvfb is not a real X server. -ac lets local clients connect; -noreset keeps
# the screen up if the first client exits.
Xvfb :1 -screen 0 "$GEOMETRY" -ac -noreset >"${LOG_DIR}/xvfb.log" 2>&1 &
i=0
while [ ! -e "/tmp/.X11-unix/X1" ] && [ ! -e "${X11_DIR}/X1" ] && [ "$i" -lt 50 ]; do
    i=$((i + 1))
    sleep 0.1
done

fluxbox >"${LOG_DIR}/fluxbox.log" 2>&1 &
xterm -geometry 110x32+24+24 -fa 'DejaVu Sans Mono' -fs 11 -title 'PteroVM' >"${LOG_DIR}/xterm.log" 2>&1 &
# Raw VNC stays on localhost. The allocated port is the noVNC page only.
x11vnc -display :1 -rfbport 5900 -localhost -forever -shared -noxdamage \
    -passwdfile "${ROOT_HOME}/vnc.pass" >"${LOG_DIR}/x11vnc.log" 2>&1 &
sleep 0.4
if ! pidof x11vnc >/dev/null 2>&1; then
    echo "x11vnc failed to start" >&2
    cat "${LOG_DIR}/x11vnc.log" >&2 || true
    exit 1
fi

NOVNC_WEB="/usr/share/novnc"
if [ -d "${BASE_DIR}/usr/share/novnc" ]; then
    NOVNC_WEB="${BASE_DIR}/usr/share/novnc"
fi

WS="$(command -v websockify || command -v websockify-3.12 || true)"
if [ -z "$WS" ]; then
    echo "websockify is missing from the embedded system" >&2
    exit 1
fi
"$WS" --web "${NOVNC_WEB}" "0.0.0.0:${PORT}" localhost:5900 >"${LOG_DIR}/novnc.log" 2>&1 &

printf 'PteroVM desktop listening on %s\n' "$PORT"
printf 'Right-click the desktop for a terminal, files, or htop.\n'
# This bash is the panel console. It is not a TTY. The xterm is.
exec "${SHELL}" --noprofile --norc
