#!/usr/bin/env bash
# docker-install.sh
# Interactive one-click Docker installer with many options.
# Supports Debian/Ubuntu and RHEL/CentOS/Fedora/Alma/Rocky.
# Requires root privileges.

set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Utility
# -------------------------
log() { echo -e "\e[1;32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $*"; }
err()  { echo -e "\e[1;31m[ERR]\e[0m $*" >&2; }
confirm() {
  local prompt="${1:-Proceed? (y/N)}"
  local default="${2:-N}"
  read -r -p "$prompt " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^([yY])$ ]]
}

# Ensure running as root or via sudo
if [[ "$EUID" -ne 0 ]]; then
  err "This script must be run as root. Re-run with sudo."
  exit 1
fi

# -------------------------
# Detect OS
# -------------------------
OS=""
OS_FAMILY=""
PKG_MANAGER=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  OS_LIKE=${ID_LIKE:-}
  if [[ "$OS" =~ ^(ubuntu|debian)$ ]]; then
    OS_FAMILY="debian"
    PKG_MANAGER="apt-get"
  elif [[ "$OS" =~ ^(centos|rhel|rocky|almalinux)$ ]] || [[ "$OS_LIKE" =~ (rhel|fedora) ]]; then
    OS_FAMILY="rhel"
    # prefer dnf if available
    if command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER="dnf"
    else
      PKG_MANAGER="yum"
    fi
  elif [[ "$OS" =~ ^(fedora)$ ]]; then
    OS_FAMILY="rhel"
    PKG_MANAGER="dnf"
  else
    # fallback checks
    if command -v apt-get >/dev/null 2>&1; then
      OS_FAMILY="debian"; PKG_MANAGER="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
      OS_FAMILY="rhel"; PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
      OS_FAMILY="rhel"; PKG_MANAGER="yum"
    else
      err "Unsupported OS. Exiting."
      exit 2
    fi
  fi
else
  err "/etc/os-release not found. Unsupported system."
  exit 2
fi

log "Detected OS: $OS (family: $OS_FAMILY), package manager: $PKG_MANAGER"

# -------------------------
# Options (interactive)
# -------------------------
echo
log "安装选项配置（按回车为默认）:"
read -r -p "是否安装 Docker Engine (y/N)？ " opt_install_docker
opt_install_docker=${opt_install_docker:-y}

read -r -p "是否安装 Docker Compose 插件（官方 plugin，推荐，y/N）？ " opt_compose_plugin
opt_compose_plugin=${opt_compose_plugin:-y}

read -r -p "是否安装 docker-compose v2 二进制（兼容旧系统/手动方式）？ (y/N) " opt_compose_bin
opt_compose_bin=${opt_compose_bin:-n}

read -r -p "是否配置 daemon.json（registry mirror / log / storage）？ (y/N) " opt_config_daemon
opt_config_daemon=${opt_config_daemon:-y}

read -r -p "是否添加当前非 root 用户到 docker 组（允许无 sudo 使用 Docker）？ (y/N) " opt_add_user
opt_add_user=${opt_add_user:-y}
CURRENT_USER="${SUDO_USER:-root}"

read -r -p "是否安装 rootless 模式（仅当需要非 root 启动 dockerd 时）？ (y/N) " opt_rootless
opt_rootless=${opt_rootless:-n}

read -r -p "是否在安装后运行 hello-world 测试镜像？ (y/N) " opt_test_hello
opt_test_hello=${opt_test_hello:-y}

# defaults for daemon config if user opts in
REGISTRY_MIRROR=""
LOG_DRIVER="json-file"
LOG_MAX_SIZE="10m"
STORAGE_DRIVER="overlay2"
INSECURE_REGISTRIES=""
if [[ "$opt_config_daemon" =~ ^([yY]) ]]; then
  read -r -p "设置 registry mirror (例如 https://registry.docker-cn.com) 或留空跳过: " REGISTRY_MIRROR
  REGISTRY_MIRROR=${REGISTRY_MIRROR:-""}
  read -r -p "日志驱动 (默认 json-file): " tmp; LOG_DRIVER=${tmp:-$LOG_DRIVER}
  read -r -p "日志单文件大小上限 (默认 ${LOG_MAX_SIZE}): " tmp; LOG_MAX_SIZE=${tmp:-$LOG_MAX_SIZE}
  read -r -p "存储驱动 (默认 ${STORAGE_DRIVER}): " tmp; STORAGE_DRIVER=${tmp:-$STORAGE_DRIVER}
  read -r -p "是否配置不安全私有仓库(insecure registries)，多个用逗号分隔 (留空跳过): " INSECURE_REGISTRIES
fi

# -------------------------
# Pre-checks & Dependencies
# -------------------------
install_packages() {
  local pkgs=("$@")
  if [[ "$PKG_MANAGER" == "apt-get" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "${pkgs[@]}"
  else
    # dnf/yum
    if command -v dnf >/dev/null 2>&1; then
      dnf makecache -y || true
      dnf install -y "${pkgs[@]}"
    else
      yum makecache -y || true
      yum install -y "${pkgs[@]}"
    fi
  fi
}

# -------------------------
# Install Docker (official)
# -------------------------
install_docker_official() {
  log "Installing Docker (official packages)..."

  if [[ "$OS_FAMILY" == "debian" ]]; then
    install_packages ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/"$OS"/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
      warn "apt install failed; trying to install core packages only"
      apt-get install -y docker-ce docker-ce-cli containerd.io || true
    }
  else
    # RHEL family
    install_packages yum-utils ca-certificates curl
    # add repo and install
    if command -v dnf >/dev/null 2>&1; then
      dnf -y install dnf-plugins-core
    fi
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true
    if command -v dnf >/dev/null 2>&1; then
      dnf makecache || true
      dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        warn "dnf install failed; trying yum"
        yum install -y docker-ce docker-ce-cli containerd.io || true
      }
    else
      yum makecache fast || true
      yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    fi
  fi

  # ensure systemd service
  systemctl daemon-reload || true
  systemctl enable --now docker || true
  log "Docker service started and enabled."
}

# -------------------------
# Install docker-compose binary (optional)
# -------------------------
install_compose_binary() {
  log "Installing docker-compose (standalone binary v2)..."
  # find latest stable release via GitHub API is network-dependent; pick v2 stable fallback
  # We'll try to fetch latest tag; if fails, fallback to 2.20.2
  COMPOSE_VERSION="2.20.2"
  if command -v curl >/dev/null 2>&1; then
    # best-effort get latest release tag
    latest=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -n "$latest" ]]; then
      COMPOSE_VERSION="${latest#v}"
    fi
  fi
  BIN_PATH="/usr/local/bin/docker-compose"
  curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o "$BIN_PATH"
  chmod +x "$BIN_PATH"
  log "Installed docker-compose ${COMPOSE_VERSION} at ${BIN_PATH}"
}

# -------------------------
# Configure daemon.json
# -------------------------
configure_daemon_json() {
  local cfg_file="/etc/docker/daemon.json"
  mkdir -p /etc/docker
  # read existing if any
  local existing="{}"
  if [[ -f "$cfg_file" ]]; then
    existing=$(cat "$cfg_file")
  fi

  # Build new JSON using simple method (jq would be nicer, but not always installed)
  # We'll create a safe file and then move
  tmpf=$(mktemp)
  cat > "$tmpf" <<EOF
{
  "storage-driver": "${STORAGE_DRIVER}",
  "log-driver": "${LOG_DRIVER}",
  "log-opts": {
    "max-size": "${LOG_MAX_SIZE}"
  }$(if [[ -n "$REGISTRY_MIRROR" ]]; then echo ",\n  \"registry-mirrors\": [\"$REGISTRY_MIRROR\"]"; fi)$(if [[ -n "$INSECURE_REGISTRIES" ]]; then
    # convert comma separated to JSON array
    echo ",\n  \"insecure-registries\": [$(printf '%s' "$INSECURE_REGISTRIES" | awk -F',' '{for(i=1;i<=NF;i++){printf "\"%s\"%s",$i,(i==NF?"":",")}}') ]"
  fi)
}
EOF
  # Validate JSON lightly
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<PYTHON_CHECK
import json,sys
try:
    with open("$tmpf") as f:
        json.load(f)
except Exception as e:
    print("JSON_ERR", e)
    sys.exit(2)
print("OK")
PYTHON_CHECK
  fi
  mv "$tmpf" "$cfg_file"
  chmod 644 "$cfg_file"
  log "Wrote $cfg_file"
  systemctl restart docker || warn "failed to restart docker; please check 'systemctl status docker'"
}

# -------------------------
# Add user to docker group
# -------------------------
add_user_to_docker() {
  local user="$1"
  if id "$user" &>/dev/null; then
    groupadd -f docker || true
    usermod -aG docker "$user" || warn "usermod returned non-zero"
    log "Added $user to docker group. They may need to re-login to apply group membership."
  else
    warn "User $user doesn't exist; skipping add to docker group."
  fi
}

# -------------------------
# Check existing docker
# -------------------------
if command -v docker >/dev/null 2>&1 && [[ "${opt_install_docker}" =~ ^([yY]) ]]; then
  warn "Docker is already installed. You can still run configuration steps or choose to reinstall/uninstall later."
  if confirm "是否重新安装/覆盖 Docker？ (y/N)" "N"; then
    REINSTALL=true
  else
    REINSTALL=false
  fi
else
  REINSTALL=false
fi

# -------------------------
# Main flow
# -------------------------
if [[ "${opt_install_docker}" =~ ^([yY]) ]]; then
  if [[ "$REINSTALL" == true ]]; then
    log "Removing existing docker packages (best-effort)..."
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
      apt-get remove -y docker docker-engine docker.io containerd runc || true
    else
      if command -v dnf >/dev/null 2>&1; then
        dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
      else
        yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
      fi
    fi
  fi

  install_docker_official
fi

# Compose plugin
if [[ "${opt_compose_plugin}" =~ ^([yY]) ]]; then
  if command -v docker-compose >/dev/null 2>&1; then
    log "A docker-compose binary already exists; skipping plugin install."
  fi
  # If plugin available as package, it's likely already installed with engine install above.
  if ! docker compose version >/dev/null 2>&1; then
    log "Ensuring docker compose plugin is installed."
    # Most distros installed plugin already with docker packages. If not, fallback to plugin install instructions:
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
      apt-get update -y
      apt-get install -y docker-compose-plugin || true
    else
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y docker-compose-plugin || true
      else
        yum install -y docker-compose-plugin || true
      fi
    fi
  fi
  log "docker compose plugin installed (or already present)."
fi

# optional binary
if [[ "${opt_compose_bin}" =~ ^([yY]) ]]; then
  install_compose_binary
fi

# configure daemon.json
if [[ "${opt_config_daemon}" =~ ^([yY]) ]]; then
  configure_daemon_json
fi

# add current user to docker group
if [[ "${opt_add_user}" =~ ^([yY]) ]]; then
  if [[ "$CURRENT_USER" != "root" ]]; then
    add_user_to_docker "$CURRENT_USER"
  else
    warn "Current sudo user not detected (running as root); skipping user add. If you want to add e.g. 'ubuntu' run: usermod -aG docker <username>"
  fi
fi

# rootless install (best-effort)
if [[ "${opt_rootless}" =~ ^([yY]) ]]; then
  log "Attempting to install dockerd-rootless-setuptool..."
  if ! command -v newuidmap >/dev/null 2>&1 || ! command -v newgidmap >/dev/null 2>&1; then
    install_packages uidmap
  fi
  # install rootless tool script
  su - "$SUDO_USER" -c "curl -fsSL https://get.docker.com/rootless | sh" || warn "Rootless installer returned non-zero. Please check output above."
  log "Rootless install attempted. Follow any printed instructions to enable it for your user."
fi

# optionally test
if [[ "${opt_test_hello}" =~ ^([yY]) ]]; then
  log "Running docker hello-world test..."
  if docker run --rm hello-world >/dev/null 2>&1; then
    log "hello-world ran successfully."
  else
    warn "hello-world test failed. If using rootless or custom daemon json, check logs: journalctl -u docker -n 200 --no-pager"
  fi
fi

# Final tips
cat <<EOF

安装完成 ✅

下一步建议：
- 如果你将非 root 用户添加到了 docker 组，请重新登录该用户以应用组权限（或运行 newgrp docker）。
- 检查 docker 服务状态：  systemctl status docker
- 如果需要查看 daemon.json：  cat /etc/docker/daemon.json
- 若需卸载或清理，请运行本脚本并选择卸载（脚本下一版本可加入交互卸载选项）

常用命令：
- docker version
- docker info
- docker compose version  (或 docker-compose --version 如果安装了二进制)
- journalctl -u docker -f

EOF
