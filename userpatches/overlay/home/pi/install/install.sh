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

setup_vscode_extensions() {
    log_info "Setting up Visual Studio Code extensions"
    code --install-extension ms-python.python
}

build_px4() {
    log_info "Building PX4"
    cd ~

    git clone https://github.com/PX4/PX4-Autopilot.git -b v1.16.1 --depth 1 --recursive
    cd PX4-Autopilot
    make px4_sitl_default
}

using_prebuilt_px4() {
    log_info "Using prebuilt PX4"
    local arch
    arch="$(dpkg --print-architecture)"

    case "${arch}" in
        amd64|arm64) ;;
        *) log_error "No prebuilt PX4 binary for architecture: ${arch}" ;;
    esac

    mv ~/PX4-Autopilot/build/px4_sitl_default/bin_"${arch}" \
       ~/PX4-Autopilot/build/px4_sitl_default/bin
}

create_ros2_workspace() {
    set +u
    source /opt/ros/${ROS_DISTRO}/setup.bash
    set -u

    log_info "Creating ROS 2 workspace"
    mkdir -p ~/ros2_ws/src
    cd ~/ros2_ws/src

    git clone https://github.com/klever-coex/clover2.git
    cd clover2
    git checkout 4120a2570e080c05b9c85e3534a4a9c78a7e1eb0
    cd ..

    git clone https://github.com/klever-coex/clover2-sim.git -b render-ogre

    rosdep update --rosdistro "${ROS_DISTRO}" -r
    rosdep install --from-paths . --ignore-src --rosdistro "${ROS_DISTRO}" -y
}

add_prebuilt_px4() {
    set +u
    source /opt/ros/${ROS_DISTRO}/setup.bash
    set -u

    log_info "Adding prebuilt PX4 to ROS 2 workspace"
    mkdir -p ~/ros2_ws/src/clover2-sim/px4_sim/prebuilt/px4_sitl_default

    cp -r ~/PX4-Autopilot/build/px4_sitl_default/bin \
      ~/PX4-Autopilot/build/px4_sitl_default/etc \
      ~/ros2_ws/src/clover2-sim/px4_sim/prebuilt/px4_sitl_default/
    rm -rf ~/PX4-Autopilot/
    
    rm ~/ros2_ws/src/clover2-sim/px4_sim/CMakeLists.txt
    cp ~/install/CMakeLists.txt ~/ros2_ws/src/clover2-sim/px4_sim/CMakeLists.txt

    cd ~/ros2_ws
    colcon build --symlink-install

    echo "source ~/ros2_ws/install/setup.bash" >> ~/.bashrc
}

install_qgroundcontrol() {
    log_info "Installing QGroundControl"
    local qgc_version="v5.1.4"
    local qgc_url="https://github.com/mavlink/qgroundcontrol/releases/download/${qgc_version}/QGroundControl-aarch64.AppImage"
    local qgc_path="/home/${USER}/.local/bin/qgroundcontrol"
    mkdir -p "$(dirname "${qgc_path}")"
    wget -O "${qgc_path}" "${qgc_url}"
    chmod +x "${qgc_path}"

    local icon_url="https://raw.githubusercontent.com/mavlink/qgroundcontrol/${qgc_version}/resources/icons/qgroundcontrol.png"
    local icon_path="/home/${USER}/.local/share/icons/qgroundcontrol.png"
    mkdir -p "$(dirname "${icon_path}")"
    wget -O "${icon_path}" "${icon_url}"

    mkdir -p ~/.local/share/applications
    cat <<EOF > ~/.local/share/applications/qgroundcontrol.desktop
[Desktop Entry]
Name=QGroundControl
Comment=Ground control station for drones
Exec=${qgc_path}
Icon=qgroundcontrol
Terminal=false
Type=Application
Categories=Development;Science;
EOF

    chmod 755 ~/.local/share/applications/qgroundcontrol.desktop
}

clean() {
    log_info "Cleaning up"
    pipx uninstall ansible || true
    sudo apt-get purge -y pipx || true

    rm -rf ~/.ansible ~/.cache/pip
}

cd "$(dirname "$0")"

sudo apt-get update -y
install_ansible
install_simulation_deps
install_vscode
setup_vscode_extensions
# build_px4
using_prebuilt_px4
create_ros2_workspace
add_prebuilt_px4
install_qgroundcontrol
clean
