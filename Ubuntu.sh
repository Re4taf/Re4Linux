#!/bin/sh

#############################
# Ubuntu Linux Installation #
#############################

ROOTFS_DIR=/home/container

# Verified Ubuntu 24.04.5 LTS Base release
UBUNTU_VERSION="24.04"
UBUNTU_FULL_VERSION="24.04.5"
PROOT_VERSION="5.3.0"

# Detect machine architecture
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
else
  printf "Unsupported CPU architecture: ${ARCH}\n"
  exit 1
fi

# Self-heal: if .installed exists from a failed run without /bin/bash, remove it
if [ -e "$ROOTFS_DIR/.installed" ] && [ ! -e "$ROOTFS_DIR/bin/bash" ]; then
    rm -f "$ROOTFS_DIR/.installed"
fi

# Download & extract Ubuntu base rootfs
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    printf "Downloading Ubuntu ${UBUNTU_FULL_VERSION} (${ARCH_ALT})...\n"
    if ! curl -fsSL "https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_FULL_VERSION}-base-${ARCH_ALT}.tar.gz" -o /tmp/rootfs.tar.gz; then
        printf "Error: Failed to download Ubuntu rootfs.\n"
        exit 1
    fi

    printf "Extracting Ubuntu rootfs...\n"
    if ! tar -xzf /tmp/rootfs.tar.gz -C "$ROOTFS_DIR"; then
        printf "Error: Failed to extract Ubuntu rootfs.\n"
        rm -f /tmp/rootfs.tar.gz
        exit 1
    fi
fi

################################
# Package Installation & Setup #
################################

if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    mkdir -p "$ROOTFS_DIR/usr/local/bin" "$ROOTFS_DIR/root"

    printf "Downloading PRoot and GoTTY...\n"
    curl -fsSL "https://github.com/sorenisanerd/gotty/releases/download/v1.5.0/gotty_v1.5.0_linux_${ARCH_ALT}.tar.gz" -o /tmp/gotty.tar.gz
    curl -fsSL "https://github.com/proot-me/proot/releases/download/v${PROOT_VERSION}/proot-v${PROOT_VERSION}-${ARCH}-static" -o "$ROOTFS_DIR/usr/local/bin/proot"

    tar -xzf /tmp/gotty.tar.gz -C "$ROOTFS_DIR/usr/local/bin"
    chmod 755 "$ROOTFS_DIR/usr/local/bin/proot" "$ROOTFS_DIR/usr/local/bin/gotty"

    # Configure DNS Resolvers
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"

    # Fix apt sandbox permissions inside PRoot
    mkdir -p "${ROOTFS_DIR}/etc/apt/apt.conf.d"
    printf 'APT::Sandbox::User "root";\n' > "${ROOTFS_DIR}/etc/apt/apt.conf.d/01-proot-sandbox"

    # Termux-style 'pkg' wrapper around apt
    cat << 'EOF' > "$ROOTFS_DIR/usr/local/bin/pkg"
#!/bin/bash
case "$1" in
  install) shift; apt update && apt install -y "$@" ;;
  uninstall|remove) shift; apt remove -y "$@" ;;
  update) apt update ;;
  upgrade) apt update && apt upgrade -y ;;
  search) shift; apt search "$@" ;;
  show) shift; apt show "$@" ;;
  *) echo "Usage: pkg {install|remove|update|upgrade|search|show} [package]" ;;
esac
EOF
    chmod 755 "$ROOTFS_DIR/usr/local/bin/pkg"

    # Clean up temporary archives
    rm -f /tmp/rootfs.tar.gz /tmp/gotty.tar.gz

    # Verify /bin/bash exists before marking installed
    if [ -e "$ROOTFS_DIR/bin/bash" ]; then
        touch "$ROOTFS_DIR/.installed"
    else
        printf "Error: /bin/bash missing after extraction.\n"
        exit 1
    fi
fi

# Print RE4 LINUX welcome banner
clear && cat << EOF

 ██████╗ ███████╗██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
 ██╔══██╗██╔════╝██║  ██║    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
 ██████╔╝█████╗  ███████║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ 
 ██╔══██╗██╔══╝  ╚════██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ 
 ██║  ██║███████╗     ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
 ╚═╝  ╚═╝╚══════╝     ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
 
 Welcome to Ubuntu ${UBUNTU_FULL_VERSION} (PRoot)!
 
 Here are some useful commands to get you started:
 
    pkg install [package] : install a package (or apt install)
    pkg remove [package]  : remove a package
    pkg update            : update the package index
    pkg upgrade           : upgrade installed packages
    pkg search [keyword]  : search for a package
    gotty -p 25628 -w bash : share your terminal in browser
 
EOF

###########################
# Start PRoot environment #
###########################

export PROOT_NO_SECCOMP=1
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

"$ROOTFS_DIR/usr/local/bin/proot" \
--rootfs="${ROOTFS_DIR}" \
--kill-on-exit \
--root-id \
--cwd=/root \
--bind=/proc \
--bind=/dev \
--bind=/sys \
--bind=/tmp \
/bin/bash -l
