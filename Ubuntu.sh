#!/bin/sh

#############################
# Ubuntu Linux Installation #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container

# Define the Ubuntu version we are going to be using.
UBUNTU_VERSION="24.04"
UBUNTU_FULL_VERSION="24.04.1"
PROOT_VERSION="5.3.0"

# Detect the machine architecture.
ARCH=$(uname -m)

# Check machine architecture to make sure it is supported.
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
else
  printf "Unsupported CPU architecture: ${ARCH}\n"
  exit 1
fi

# Download & decompress the Ubuntu base root file system if not already installed.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    printf "Downloading Ubuntu ${UBUNTU_FULL_VERSION} (${ARCH_ALT})...\n"
    curl -Lo /tmp/rootfs.tar.gz \
    "https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_FULL_VERSION}-base-${ARCH_ALT}.tar.gz"
    
    printf "Extracting Ubuntu rootfs...\n"
    tar -xzf /tmp/rootfs.tar.gz -C $ROOTFS_DIR
fi

################################
# Package Installation & Setup #
################################

if [ ! -e $ROOTFS_DIR/.installed ]; then
    mkdir -p $ROOTFS_DIR/usr/local/bin

    # Download PRoot and GoTTY
    curl -Lo /tmp/gotty.tar.gz "https://github.com/sorenisanerd/gotty/releases/download/v1.5.0/gotty_v1.5.0_linux_${ARCH_ALT}.tar.gz"
    curl -Lo $ROOTFS_DIR/usr/local/bin/proot "https://github.com/proot-me/proot/releases/download/v${PROOT_VERSION}/proot-v${PROOT_VERSION}-${ARCH}-static"

    # Extract GoTTY
    tar -xzf /tmp/gotty.tar.gz -C $ROOTFS_DIR/usr/local/bin

    # Make PRoot and GoTTY executable
    chmod 755 $ROOTFS_DIR/usr/local/bin/proot $ROOTFS_DIR/usr/local/bin/gotty

    # Configure DNS Resolvers
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > ${ROOTFS_DIR}/etc/resolv.conf

    # Fix apt sandbox permissions inside PRoot so 'apt update' doesn't fail as _apt user
    mkdir -p ${ROOTFS_DIR}/etc/apt/apt.conf.d
    printf 'APT::Sandbox::User "root";\n' > ${ROOTFS_DIR}/etc/apt/apt.conf.d/01-proot-sandbox

    # Add a Termux-style 'pkg' wrapper around apt
    cat << 'EOF' > $ROOTFS_DIR/usr/local/bin/pkg
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
    chmod 755 $ROOTFS_DIR/usr/local/bin/pkg

    # Clean up temporary files
    rm -rf /tmp/rootfs.tar.gz /tmp/gotty.tar.gz

    # Mark installation complete
    touch $ROOTFS_DIR/.installed
fi

# Print welcome banner
clear && cat << EOF

 ██████╗ ███████╗ ██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
 ██╔══██╗██╔════╝ ██║  ██║    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
 ██████╔╝█████╗   ███████║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ 
 ██╔══██╗██╔══╝   ╚════██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ 
 ██║  ██║███████╗      ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
 ╚═╝  ╚═╝╚══════╝      ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
 
 Welcome to Ubuntu ${UBUNTU_VERSION} (PRoot)!
 
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

$ROOTFS_DIR/usr/local/bin/proot \
--rootfs="${ROOTFS_DIR}" \
--link2symlink \
--kill-on-exit \
--root-id \
--cwd=/root \
--bind=/proc \
--bind=/dev \
--bind=/sys \
--bind=/tmp \
/bin/bash -l
