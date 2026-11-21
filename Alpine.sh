#!/bin/sh

##############################################
# Alpine Linux (Harbor) + XFCE + Browser VNC #
##############################################

ROOTFS_DIR=/home/container
PROOT_BIN="${ROOTFS_DIR}/usr/local/bin/proot"
ALPINE_VERSION="3.18"
ALPINE_FULL_VERSION="3.18.3"
PROOT_VERSION="5.3.0"
WEB_VNC_PORT="${SERVER_PORT:-25628}"
VNC_DISPLAY=":1"
VNC_INTERNAL_PORT="5901"

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH_ALT="arm64"
else
    printf "Unsupported CPU architecture: %s\n" "${ARCH}"
    exit 1
fi

run_proot() {
    "${PROOT_BIN}" \
        --rootfs="${ROOTFS_DIR}" \
        --link2symlink \
        --kill-on-exit \
        --root-id \
        --cwd=/root \
        --bind=/proc \
        --bind=/dev \
        --bind=/sys \
        --bind=/tmp \
        /bin/sh -c "$1"
}

###########################################
# 1. Alpine Base RootFS + Static PRoot    #
###########################################

if [ ! -e "${ROOTFS_DIR}/.installed" ] || [ ! -x "${PROOT_BIN}" ] || [ ! -x "${ROOTFS_DIR}/sbin/apk" ]; then
    rm -f "${ROOTFS_DIR}/.installed"

    echo "[1/4] Downloading Alpine Linux ${ALPINE_FULL_VERSION} (${ARCH}) minirootfs..."
    curl -fL --progress-bar -o /tmp/rootfs.tar.gz \
        "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_FULL_VERSION}-${ARCH}.tar.gz"
    tar -xzf /tmp/rootfs.tar.gz -C "${ROOTFS_DIR}"

    echo "[2/4] Resolving apk-tools-static, downloading gotty, and downloading static proot..."
    APKINDEX_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main/${ARCH}/APKINDEX.tar.gz"
    rm -rf /tmp/apkindex_dir && mkdir -p /tmp/apkindex_dir
    curl -fLs "${APKINDEX_URL}" | tar -xz -C /tmp/apkindex_dir
    APK_TOOLS_VERSION=$(awk '
        /^P:apk-tools-static$/ { found=1 }
        found && /^V:/ { sub(/^V:/, ""); print; exit }
    ' /tmp/apkindex_dir/APKINDEX)

    if [ -z "${APK_TOOLS_VERSION}" ]; then
        echo "Failed to resolve apk-tools-static version from APKINDEX"
        exit 1
    fi

    curl -fL --progress-bar -o /tmp/apk-tools-static.apk \
        "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main/${ARCH}/apk-tools-static-${APK_TOOLS_VERSION}.apk"
    curl -fL --progress-bar -o /tmp/gotty.tar.gz \
        "https://github.com/sorenisanerd/gotty/releases/download/v1.5.0/gotty_v1.5.0_linux_${ARCH_ALT}.tar.gz"
    mkdir -p "${ROOTFS_DIR}/usr/local/bin"
    curl -fL --progress-bar -o "${PROOT_BIN}" \
        "https://github.com/proot-me/proot/releases/download/v${PROOT_VERSION}/proot-v${PROOT_VERSION}-${ARCH}-static"

    rm -rf /tmp/sbin && mkdir -p /tmp/sbin
    tar -xzf /tmp/apk-tools-static.apk -C /tmp/
    tar -xzf /tmp/gotty.tar.gz -C "${ROOTFS_DIR}/usr/local/bin"
    /tmp/sbin/apk.static -X "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main/" -U --allow-untrusted --root "${ROOTFS_DIR}" add alpine-base apk-tools
    chmod 755 "${PROOT_BIN}" "${ROOTFS_DIR}/usr/local/bin/gotty"

    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    rm -rf /tmp/apk-tools-static.apk /tmp/gotty.tar.gz /tmp/rootfs.tar.gz /tmp/sbin /tmp/apkindex_dir
fi

###########################################
# 2. Install XFCE4, TigerVNC & noVNC      #
###########################################

if [ ! -e "${ROOTFS_DIR}/.vnc_ready" ] || [ ! -x "${ROOTFS_DIR}/usr/bin/startxfce4" ] || [ ! -x "${ROOTFS_DIR}/usr/bin/websockify" ]; then
    echo "[3/4] Enabling Alpine community repo & installing XFCE4, TigerVNC, noVNC..."
    run_proot '
        cat << "REPOS" > /etc/apk/repositories
https://dl-cdn.alpinelinux.org/alpine/v3.18/main
https://dl-cdn.alpinelinux.org/alpine/v3.18/community
REPOS
        apk update
        apk add --no-cache \
            xfce4 xfce4-terminal dbus \
            tigervnc novnc py3-websockify \
            font-dejavu curl ca-certificates
    '

    echo "[4/4] Configuring xstartup and default VNC password (alpine)..."
    run_proot '
        mkdir -p /root/.vnc
        cat << "XSTARTUP" > /root/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
dbus-launch --exit-with-session startxfce4 &
XSTARTUP
        chmod 755 /root/.vnc/xstartup
        printf "alpine\nalpine\n" | vncpasswd -f > /root/.vnc/passwd
        chmod 600 /root/.vnc/passwd
    '

    touch "${ROOTFS_DIR}/.vnc_ready"
fi

touch "${ROOTFS_DIR}/.installed"

###########################################
# 3. Start TigerVNC + Browser noVNC Proxy  #
###########################################

run_proot "
    pkill -f 'Xtigervnc.*${VNC_DISPLAY}' >/dev/null 2>&1 || true
    pkill -f 'websockify.*${WEB_VNC_PORT}' >/dev/null 2>&1 || true
    rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
    vncserver ${VNC_DISPLAY} -geometry 1280x720 -depth 24 -rfbport ${VNC_INTERNAL_PORT} -PasswordFile /root/.vnc/passwd -localhost yes >/tmp/vnc.log 2>&1
    nohup websockify --web /usr/share/novnc 0.0.0.0:${WEB_VNC_PORT} 127.0.0.1:${VNC_INTERNAL_PORT} >/tmp/novnc.log 2>&1 &
"

clear && cat << EOF

  █████╗ ██╗     ██████╗ ██╗███╗   ██╗███████╗
 ██╔══██╗██║     ██╔══██╗██║████╗  ██║██╔════╝
 ███████║██║     ██████╔╝██║██╔██╗ ██║█████╗  
 ██╔══██║██║     ██╔═══╝ ██║██║╚██╗██║██╔══╝  
 ██║  ██║███████╗██║     ██║██║ ╚████║███████╗
 ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚══════╝
 
 Welcome to Alpine Linux (Harbor) + XFCE + Browser VNC!

  -> Browser VNC URL : http://zannserver:${WEB_VNC_PORT}/vnc.html
  -> VNC Password    : alpine
  -> Stop VNC        : vncserver -kill ${VNC_DISPLAY}
  -> Share Terminal  : gotty -p [port] -w ash

EOF

exec "${PROOT_BIN}" \
    --rootfs="${ROOTFS_DIR}" \
    --link2symlink \
    --kill-on-exit \
    --root-id \
    --cwd=/root \
    --bind=/proc \
    --bind=/dev \
    --bind=/sys \
    --bind=/tmp \
    /bin/sh
