#!/bin/sh

#############################################
# Pterodactyl Ubuntu XFCE + VNC (Harbor)    #
#############################################

ROOTFS_DIR=/home/container
PROOT_BIN="${ROOTFS_DIR}/usr/local/bin/proot"
UBUNTU_RELEASE="24.04.5"
PROOT_VERSION="5.3.0"
VNC_PORT="${SERVER_PORT:-25628}"

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
        --cwd=/ \
        --bind=/dev \
        --bind=/proc \
        --bind=/sys \
        --bind=/tmp \
        /usr/bin/env -i \
        HOME=/root \
        TERM=xterm \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        LANG=C.UTF-8 \
        /bin/bash -c "$1"
}

###########################################
# Download & Extract Ubuntu + Static PRoot #
###########################################

if [ ! -e "${ROOTFS_DIR}/.installed" ] || [ ! -x "${ROOTFS_DIR}/usr/bin/env" ]; then
    rm -f "${ROOTFS_DIR}/.installed" /tmp/ubuntu-rootfs.tar.gz

    echo "[1/4] Downloading Ubuntu ${UBUNTU_RELEASE} (${ARCH_ALT}) base rootfs..."
    curl -fL --progress-bar -o /tmp/ubuntu-rootfs.tar.gz \
        "https://cdimage.ubuntu.com/ubuntu-base/releases/noble/release/ubuntu-base-${UBUNTU_RELEASE}-base-${ARCH_ALT}.tar.gz"

    echo "[2/4] Extracting rootfs and downloading static PRoot..."
    tar -xzf /tmp/ubuntu-rootfs.tar.gz -C "${ROOTFS_DIR}" --exclude='dev/*'
    rm -f /tmp/ubuntu-rootfs.tar.gz

    mkdir -p "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/root"
    curl -fL --progress-bar -o "${PROOT_BIN}" \
        "https://github.com/proot-me/proot/releases/download/v${PROOT_VERSION}/proot-v${PROOT_VERSION}-${ARCH}-static"
    chmod 755 "${PROOT_BIN}"

    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    echo "127.0.0.1 localhost" > "${ROOTFS_DIR}/etc/hosts"

    printf 'APT::Get::AllowUnauthenticated "true";\nAcquire::AllowInsecureRepositories "true";\n' > /etc/apt/apt.conf.d/99-allow-unauth

    echo "[3/4] Installing XFCE4 and TigerVNC inside Ubuntu..."
    run_proot '
        mkdir -p /root
        grep -q ":971:" /etc/group || echo "hostgroup971:x:971:" >> /etc/group
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get upgrade -y
        apt-get install -y --no-install-recommends
        apt-get install xfce4
        apt-get install xfce4-goodies
        apt-get install xfce4-terminal
        apt-get install dbus-x11
        apt-get install tigervnc-standalone-server
        apt-get install tigervnc-common
        sudo wget curl ca-certificates nano less fonts-dejavu-core
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    '

    echo "[4/4] Configuring TigerVNC startup script and default password ('ubuntu')..."
    run_proot '
        mkdir -p /root/.vnc
        cat << "EOF" > /root/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR
dbus-launch --exit-with-session startxfce4 &
EOF
        chmod +x /root/.vnc/xstartup
        printf "ubuntu\nubuntu\nn\n" | vncpasswd >/dev/null 2>&1
    '

    touch "${ROOTFS_DIR}/.installed"
fi

###########################################
# Ensure Group & Start VNC on Server Port #
###########################################

run_proot "
    mkdir -p /root
    grep -q ':971:' /etc/group || echo 'hostgroup971:x:971:' >> /etc/group
    vncserver -kill :1 >/dev/null 2>&1 || true
    rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
    vncserver :1 -rfbport ${VNC_PORT} -geometry 1280x720 -depth 24 -localhost no || true
"

clear && cat << EOF

 ██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗
 ██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║
 ██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║
 ██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║
 ╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝
  ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝ 

 Welcome to Ubuntu 24.04.5 LTS (XFCE + TigerVNC PRoot)!

  -> VNC Address  : zannserver:${VNC_PORT} (Display :1)
  -> VNC Password : ubuntu (change with: vncpasswd)
  -> Stop VNC     : vncserver -kill :1
  -> Restart VNC  : vncserver :1 -rfbport ${VNC_PORT} -geometry 1280x720 -depth 24 -localhost no

EOF

exec "${PROOT_BIN}" \
    --rootfs="${ROOTFS_DIR}" \
    --link2symlink \
    --kill-on-exit \
    --root-id \
    --cwd=/root \
    --bind=/dev \
    --bind=/proc \
    --bind=/sys \
    --bind=/tmp \
    /usr/bin/env -i \
    HOME=/root \
    TERM=xterm \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    /bin/bash --login
