#!/bin/bash
set -euo pipefail

ROS_DISTRO=jazzy
COLLECTION_SOURCE="/tmp/overlay/ansible"
ANSIBLE_VERSION="10.7.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_stage() { echo -e "${BLUE}[STAGE]${NC} $*"; }

install_ansible() {
    log_info "Installing Ansible ${ANSIBLE_VERSION} via pipx"

    sudo apt-get install -y pipx make
    pipx install --include-deps "ansible==${ANSIBLE_VERSION}"

    [[ -f "${COLLECTION_SOURCE}/galaxy.yml" ]] || \
        log_error "Local clover2-dev Ansible collection not found at ${COLLECTION_SOURCE}"

    log_info "Installing local clover2-dev Ansible collection"
    ~/.local/bin/ansible-galaxy collection install "${COLLECTION_SOURCE}"
}

install_simulation_deps() {
    log_info "Installing ROS 2 ${ROS_DISTRO} via Ansible"
    ~/.local/bin/ansible-playbook -vv \
        clover2.dev.install_deps --tags simulation \
        -i ./inventory.ini \
        -e rosdistro=${ROS_DISTRO}
}

install_vscode() {
    log_info "Installing Visual Studio Code via Ansible"
    ~/.local/bin/ansible-playbook -vv \
        clover2.dev.install_vscode --tags vscode \
        -i ./inventory.ini
}

build_px4() {
    log_info "Building PX4"
    mkdir -p ~/tmp
    cd ~/tmp

    git clone https://github.com/PX4/PX4-Autopilot.git -b v1.16.1 --depth 1 --recursive
    cd PX4-Autopilot
    make px4_sitl_default
}

create_ros2_workspace() {
    set +u
    source /opt/ros/${ROS_DISTRO}/setup.bash
    set -u

    log_info "Creating ROS 2 workspace"
    mkdir -p ~/ros2_ws/src
    cd ~/ros2_ws/src
    git clone https://github.com/klever-coex/clover2.git
    git clone https://github.com/klever-coex/clover2-sim.git

    rosdep update --rosdistro "${ROS_DISTRO}" -r
    rosdep install --from-paths . --ignore-src --rosdistro "${ROS_DISTRO}" -y
}

add_prebuilt_px4() {
    set +u
    source /opt/ros/${ROS_DISTRO}/setup.bash
    set -u

    log_info "Adding prebuilt PX4 to ROS 2 workspace"
    mkdir -p ~/ros2_ws/src/clover2-sim/px4_sim/prebuilt/px4_sitl_default

    cp -r ~/tmp/PX4-Autopilot/build/px4_sitl_default/bin \
      ~/tmp/PX4-Autopilot/build/px4_sitl_default/etc \
      ~/ros2_ws/src/clover2-sim/px4_sim/prebuilt/px4_sitl_default/
    rm -rf ~/tmp/
    
    rm ~/ros2_ws/src/clover2-sim/px4_sim/CMakeLists.txt
    cp ~/install/CMakeLists.txt ~/ros2_ws/src/clover2-sim/px4_sim/CMakeLists.txt

    cd ~/ros2_ws
    CMAKE_BUILD_PARALLEL_LEVEL=1 MAKEFLAGS="-j1" colcon build --symlink-install --executor sequential
}

cd "$(dirname "$0")"

sudo apt-get update -y
install_ansible
install_simulation_deps
install_vscode
build_px4
create_ros2_workspace
add_prebuilt_px4
