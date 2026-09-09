#!/bin/bash
#
# customize-image.sh — Clover2 image customization
#
# Executed inside chroot during Armbian image build.
# Installs ROS 2 Jazzy + MAVROS + dependencies via Ansible.
#
# Arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP

set -euo pipefail

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

USER=pi
ROS_DISTRO=jazzy

# --- Pinned versions (reproducible builds) ---
ANSIBLE_VERSION="10.7.0"
COLLECTION_SOURCE="/tmp/overlay/ansible"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_stage() { echo -e "${BLUE}[STAGE]${NC} $*"; }

create_user() {
    if ! id ${USER} &>/dev/null; then
        useradd -m -s /bin/bash \
            -G sudo,adm,dialout,cdrom,plugdev,video,audio,netdev,render \
            ${USER}
        echo "${USER}:raspberry" | chpasswd
        log_info "Created user: ${USER}"

        # Add nopasswd sudo for ${USER}
        echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${USER}
        chmod 0440 /etc/sudoers.d/${USER}
    fi
}

install_default_kernel() {
    local generic_kernel_version="6.8.0-139-generic"
    
    apt-get update
    apt-get install -y \
        "linux-image-${generic_kernel_version}" \
        "linux-modules-${generic_kernel_version}" \
        "linux-modules-extra-${generic_kernel_version}"
}

Main() {
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    create_user

    # # --- Copy overlay files to rootfs ---
    if [[ -d /tmp/overlay/home ]]; then
        cp -r /tmp/overlay/home/* /home/
        chown -R ${USER}:${USER} /home/${USER}
        chmod -R 755 /home/${USER}

        log_info "Overlay /home applied."
    fi

    mkdir -p /dev/shm
    chmod 1777 /dev/shm

    log_info "Running install.sh as ${USER}"
    sudo -u ${USER} bash -c "~/install/install.sh"

    # --- Cleanup build artifacts ---
    rm -rf /home/${USER}/install/

    # rm -f /root/.not_logged_in_yet

    log_info "Customization complete."
}

Main
