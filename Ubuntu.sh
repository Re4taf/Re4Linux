#!/data/data/com.termux/files/usr/bin/bash

#############################################
# Termux Ubuntu XFCE + VNC (Harbor-Style)   #
#############################################

# Define the root directory inside Termux home
ROOTFS_DIR="$HOME/ubuntu-rootfs"

# Ubuntu Base release configuration (24.04 LTS Noble)
UBUNTU_VERSION="24.04"
UBUNTU_RELEASE="24.04.1"

# Detect machine architecture and map to Ubuntu tarball naming
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH_ALT="arm64"
else
    printf "Unsupported CPU architecture: %s\n" "${ARCH}"
    exit 1
fi

# Ensure host Termux dependencies (proot, curl, tar, pulseaudio) are present
if ! command -v proot >/dev/null 2>&1 || ! command -v pulseaudio >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    echo "[*] Installing required Termux host packages..."
    pkg update -y && pkg install -y proot curl tar pulseaudio
fi

# Helper function to execute commands inside the PRoot Ubuntu environment
run_proot() {
    unset LD_PRELOAD
    proot \
        --rootfs="${ROOTFS_DIR}" \
        --link2symlink \
        --kill-on-exit \
        --root-id \
        --cwd=/root \
        --bind=/dev \
        --bind=/proc \
        --bind=/sys \
        --bind=/data/data/com.termux/files/usr/tmp:/tmp \
        /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        LANG=C.UTF-8 \
        /bin/bash -c "$1"
}

###########################################
# Download & Extract Ubuntu Base RootFS   #
###########################################

if [ ! -e "${ROOTFS_DIR}/.installed" ]; then
    echo "[1/4] Downloading Ubuntu ${UBUNTU_RELEASE} (${ARCH_ALT}) base rootfs..."
    mkdir -p "${ROOTFS_DIR}"
    curl -Lo "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/ubuntu-rootfs.tar.gz" \
        "https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_RELEASE}-base-${ARCH_ALT}.tar.gz"

    echo "[2/4] Extracting rootfs to ${ROOTFS_DIR}..."
    tar -xzf "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/ubuntu-rootfs.tar.gz" -C "${ROOTFS_DIR}" --exclude='dev/*'
    rm -f "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/ubuntu-rootfs.tar.gz"

    # Configure DNS nameservers
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    echo "127.0.0.1 localhost" > "${ROOTFS_DIR}/etc/hosts"
fi

###########################################
# Package Installation & XFCE/VNC Setup   #
###########################################

if [ ! -e "${ROOTFS_DIR}/.installed" ]; then
    echo "[3/4] Installing XFCE4, TigerVNC, and D-Bus inside Ubuntu (this may take a few minutes)..."
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

        # Set default VNC password to "ubuntu"
        printf "ubuntu\nubuntu\nn\n" | vncpasswd >/dev/null 2>&1
    '

    # Mark installation complete (Harbor style flag)
    touch "${ROOTFS_DIR}/.installed"
fi

###########################################
# Start Audio, VNC Server & Enter PRoot   #
###########################################

# Start PulseAudio on Termux host for audio forwarding
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null

# Clean stale VNC locks and start TigerVNC inside Ubuntu
run_proot '
    vncserver -kill :1 >/dev/null 2>&1
    rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
    export PULSE_SERVER=127.0.0.1
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
 
  -> VNC Server   : 127.0.0.1:5901 (Display :1)
  -> VNC Password : ubuntu (change with: vncpasswd)
  -> Audio Server : PulseAudio active on 127.0.0.1
  -> Stop VNC     : vncserver -kill :1
  -> Restart VNC  : vncserver :1 -geometry 1280x720 -depth 24 -localhost no

EOF

# Drop directly into the interactive Ubuntu PRoot shell (Harbor style)
unset LD_PRELOAD
exec proot \
    --rootfs="${ROOTFS_DIR}" \
    --link2symlink \
    --kill-on-exit \
    --root-id \
    --cwd=/root \
    --bind=/dev \
    --bind=/proc \
    --bind=/sys \
    --bind=/data/data/com.termux/files/usr/tmp:/tmp \
    /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    PULSE_SERVER=127.0.0.1 \
    /bin/bash --login
