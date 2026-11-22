#!/bin/sh
# Desktop inside the embedded Alpine system. The panel port is already public.
set -eu

# Detect whether we are on the outer host/archive root (where ./proot-x86_64 exists)
# or already inside the Alpine rootfs.
if [ -x "./proot-x86_64" ] || [ -f "./proot-x86_64" ]; then
    ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    chmod +x "$ROOT_DIR/proot-x86_64" "$ROOT_DIR/start.sh" 2>/dev/null || true
    mkdir -p "$ROOT_DIR/tmp" "$ROOT_DIR/dev" "$ROOT_DIR/proc" "$ROOT_DIR/sys"
    export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$ROOT_DIR/tmp}"
    exec "$ROOT_DIR/proot-x86_64" \
        -r "$ROOT_DIR" \
        -w /root \
        -b /dev \
        -b /proc \
        -b /sys \
        -b /etc/resolv.conf \
        /bin/sh "$ROOT_DIR/start.sh"
fi

unset WAYLAND_DISPLAY WAYLAND_SOCKET || true
export HOME=/root
export DISPLAY=:1
export XDG_SESSION_TYPE=x11
export SHELL=/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd /root

# Restore executable permissions on binaries, shared libs, and scripts stripped by archive flattening
for d in /bin /sbin /usr/bin /usr/sbin /usr/local/bin; do
    if [ -d "$d" ]; then
        chmod -R a+rX "$d" 2>/dev/null || true
    fi
done
if [ -d /lib ]; then
    chmod a+rX /lib/*.so* 2>/dev/null || true
fi
if [ -d /usr/lib ]; then
    chmod -R a+rX /usr/lib 2>/dev/null || true
fi

# Repair flattened symlinks (0-byte files left behind when symlinks were not preserved)
ensure_link() {
    target="$1"
    linkpath="$2"
    if [ ! -e "$linkpath" ] || [ ! -s "$linkpath" ]; then
        mkdir -p "$(dirname -- "$linkpath")"
        rm -rf "$linkpath"
        ln -s "$target" "$linkpath"
    fi
}

# 1. musl x86_64 dynamic linker
if [ -s /lib/libc.musl-x86_64.so.1 ]; then
    ensure_link "libc.musl-x86_64.so.1" "/lib/ld-musl-x86_64.so.1"
fi

# 2. BusyBox applets if /bin/busybox exists
if [ -x /bin/busybox ]; then
    for app in sh ash bash cat ls cp mv rm mkdir rmdir ln chmod chown chgrp \
               echo env grep sed awk cut tr head tail wc sort uniq find xargs \
               tar gzip unzip ps kill killall sleep mount umount df du id whoami \
               uname hostname ip ifconfig route ping wget nc vi pidof; do
        if [ ! -x "/bin/$app" ] && [ ! -L "/bin/$app" ]; then
            ensure_link "/bin/busybox" "/bin/$app"
        fi
    done
    if [ ! -x /usr/bin/env ] && [ ! -L /usr/bin/env ]; then
        ensure_link "/bin/busybox" "/usr/bin/env"
    fi
fi

# Fallback if /bin/bash was a 0-byte file and no real bash binary is present
if [ ! -x /bin/bash ]; then
    if [ -x /usr/bin/bash ]; then
        ensure_link "/usr/bin/bash" "/bin/bash"
    elif [ -x /bin/ash ]; then
        ensure_link "/bin/ash" "/bin/bash"
    elif [ -x /bin/sh ]; then
        ensure_link "/bin/sh" "/bin/bash"
    fi
fi

GEOMETRY="${VNC_GEOMETRY:-1280x720x24}"
PORT="${SERVER_PORT:-8080}"

# Classic VNC keeps 8 characters. x11vnc -storepasswd writes a binary blob, and
# -passwdfile on this build reads a text line (fgets). A blob with a NUL or
# newline makes x11vnc exit, and a blob without one is not the typed password.
PASS=$(printf '%s' "${VNC_PASSWORD:-pterovm}" | tr -d '\r\n')
PASS=$(printf '%.8s' "$PASS")
if [ -z "$PASS" ]; then
    PASS=pterovm
fi

mkdir -p /root /var/log
mkdir -p /tmp/.X11-unix 2>/dev/null || true
chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true
umask 077
printf '%s\n' "$PASS" > /root/vnc.pass
chmod 600 /root/vnc.pass

# Xvfb is not a real X server. -ac lets local clients connect; -noreset keeps
# the screen up if the first client exits.
Xvfb :1 -screen 0 "$GEOMETRY" -ac -noreset >/var/log/xvfb.log 2>&1 &
i=0
while [ ! -e /tmp/.X11-unix/X1 ] && [ "$i" -lt 50 ]; do
    i=$((i + 1))
    sleep 0.1
done

fluxbox >/var/log/fluxbox.log 2>&1 &
xterm -geometry 110x32+24+24 -fa 'DejaVu Sans Mono' -fs 11 -title 'PteroVM' >/var/log/xterm.log 2>&1 &

# Raw VNC stays on localhost. The allocated port is the noVNC page only.
x11vnc -display :1 -rfbport 5900 -localhost -forever -shared -noxdamage \
    -passwdfile /root/vnc.pass >/var/log/x11vnc.log 2>&1 &
sleep 0.4

# Use kill -0 fallback in case pidof wasn't linked as an applet
x11vnc_running=0
if command -v pidof >/dev/null 2>&1 && pidof x11vnc >/dev/null 2>&1; then
    x11vnc_running=1
elif [ -s /var/log/x11vnc.log ] && ! grep -qi "error\|failed" /var/log/x11vnc.log 2>/dev/null; then
    x11vnc_running=1
fi

if [ "$x11vnc_running" -eq 0 ]; then
    echo "x11vnc failed to start" >&2
    cat /var/log/x11vnc.log >&2 || true
    exit 1
fi

WS="$(command -v websockify || command -v websockify-3.12 || true)"
if [ -z "$WS" ]; then
    echo "websockify is missing from the embedded system" >&2
    exit 1
fi
"$WS" --web /usr/share/novnc "0.0.0.0:${PORT}" localhost:5900 >/var/log/novnc.log 2>&1 &

printf 'PteroVM desktop listening on %s\n' "$PORT"
printf 'Right-click the desktop for a terminal, files, or htop.\n'

# This bash is the panel console. It is not a TTY. The xterm is.
exec /bin/bash --noprofile --norc
