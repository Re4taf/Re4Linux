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
# 1. Download & Extract Base RootFS       #
###########################################

if [ ! -x "${ROOTFS_DIR}/usr/bin/env" ] || [ ! -x "${PROOT_BIN}" ]; then
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
fi

###########################################
# 2. Fix GPG/Sources & Install XFCE4+VNC  #
###########################################

if [ ! -x "${ROOTFS_DIR}/usr/bin/vncserver" ] || [ ! -x "${ROOTFS_DIR}/usr/bin/startxfce4" ] || [ ! -x "${ROOTFS_DIR}/usr/bin/less" ]; then
    echo "[3/4] Fixing APT keyring/sources and installing XFCE4 + TigerVNC..."
    run_proot '
        mkdir -p /root /etc/apt/apt.conf.d /etc/apt/trusted.gpg.d
        grep -q ":971:" /etc/group || echo "hostgroup971:x:971:" >> /etc/group

        rm -f /etc/apt/sources.list
        if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
            sed -i "s/Components: main/Components: main universe/g" /etc/apt/sources.list.d/ubuntu.sources
        else
            printf "deb http://archive.ubuntu.com/ubuntu noble main universe\ndeb http://archive.ubuntu.com/ubuntu noble-updates main universe\ndeb http://archive.ubuntu.com/ubuntu noble-security main universe\n" > /etc/apt/sources.list
        fi

        cat << "APTCONF" > /etc/apt/apt.conf.d/99-proot-allow-unauth
APT::Get::AllowUnauthenticated "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APTCONF

        if command -v gpg >/dev/null 2>&1; then
            gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 871920D1991BC93C >/dev/null 2>&1 || true
            gpg --batch --export 871920D1991BC93C > /etc/apt/trusted.gpg.d/ubuntu-noble.gpg 2>/dev/null || true
        fi

        export DEBIAN_FRONTEND=noninteractive
        apt-get update --allow-insecure-repositories || apt-get update
        apt-get install -y --allow-unauthenticated --no-install-recommends \
            ubuntu-keyring ca-certificates gnupg \
            xfce4 xfce4-goodies xfce4-terminal \
            dbus-x11 tigervnc-standalone-server tigervnc-common \
            sudo wget curl nano less fonts-dejavu-core
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    '
fi

if [ ! -x "${ROOTFS_DIR}/root/.vnc/xstartup" ] || [ ! -f "${ROOTFS_DIR}/root/.vnc/passwd" ]; then
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
fi

touch "${ROOTFS_DIR}/.installed"

###########################################
# 3. Start VNC Server & Enter PRoot       #
###########################################

run_proot "
    mkdir -p /root
    grep -q ':971:' /etc/group || echo 'hostgroup971:x:971:' >> /etc/group
    vncserver -kill :1 >/dev/null 2>&1 || true
    rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
    vncserver :1 -rfbport ${VNC_PORT} -geometry 1280x720 -depth 24 -localhost no
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
