#!/bin/sh

#############################################
# Pterodactyl Ubuntu XFCE + VNC (Harbor)    #
#############################################

ROOTFS_DIR=/home/container
PROOT_BIN="${ROOTFS_DIR}/usr/local/bin/proot"
UBUNTU_VERSION="24.04"
UBUNTU_RELEASE="24.04.1"
PROOT_VERSION="5.3.0"

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

if [ ! -e "${ROOTFS_DIR}/.installed" ]; then
    echo "[1/4] Downloading Ubuntu ${UBUNTU_RELEASE} (${ARCH_ALT}) base rootfs..."
    curl -Lo /tmp/ubuntu-rootfs.tar.gz \
        "https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_RELEASE}-base-${ARCH_ALT}.tar.gz"

    echo "[2/4] Extracting rootfs and downloading static PRoot..."
    tar -xzf /tmp/ubuntu-rootfs.tar.gz -C "${ROOTFS_DIR}" --exclude='dev/*'
    rm -f /tmp/ubuntu-rootfs.tar.gz

    mkdir -p "${ROOTFS_DIR}/usr/local/bin"
    curl -Lo "${PROOT_BIN}" \
        "https://github.com/proot-me/proot/releases/download/v${PROOT_VERSION}/proot-v${PROOT_VERSION}-${ARCH}-static"
    chmod 755 "${PROOT_BIN}"

    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    echo "127.0.0.1 localhost" > "${ROOTFS_DIR}/etc/hosts"
fi

###########################################
# Install XFCE4, D-Bus & TigerVNC         #
###########################################

if [ ! -e "${ROOTFS_DIR}/.installed" ]; then
    echo "[3/4] Installing XFCE4 and TigerVNC inside Ubuntu..."
    run_proot '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get upgrade -y
        apt-get install -y --no-install-recommends \
            xfce4 xfce4-goodies xfce4-terminal \
            dbus-x11 tigervnc-standalone-server tigervnc-common \
            sudo wget curl ca-certificates nano fonts-dejavu-core
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
# Start VNC Server & Enter PRoot          #
###########################################

run_proot '
    vncserver -kill :1 >/dev/null 2>&1
    rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
    vncserver :1 -geometry 1280x720 -depth 24 -localhost no
'

clear && cat << 'EOF'

 ██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗
 ██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║
 ██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║
 ██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║
 ╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝
  ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝ 

 Welcome to Ubuntu 24.04 LTS (XFCE + TigerVNC PRoot)!

  -> VNC Display  : :1 (Port 5901)
  -> VNC Password : ubuntu
  -> Stop VNC     : vncserver -kill :1
  -> Restart VNC  : vncserver :1 -geometry 1280x720 -depth 24 -localhost no

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
