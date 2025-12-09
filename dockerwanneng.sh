#!/bin/bash

# =========================================================
# Description: Docker Setup with Version Selection
# Supported OS: CentOS 7+, AlmaLinux, Rocky Linux, Ubuntu, Debian
# Features: Version Select, Mirror, Log Rotate, Portainer
# =========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 检查 Root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# 全局变量
DOCKER_VERSION=""
COMPOSE_VERSION=""
SOURCE_CHOICE=""
OS_RELEASE=""

# 1. 系统检测
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        OS_RELEASE="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        OS_RELEASE="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        OS_RELEASE="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        OS_RELEASE="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        OS_RELEASE="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        OS_RELEASE="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        OS_RELEASE="centos"
    else
        echo -e "${RED}未检测到支持的操作系统版本，脚本终止。${PLAIN}"
        exit 1
    fi
}

# 2. 准备基础环境 & 配置源 (必须先配置源才能列出版本)
prepare_repo() {
    echo -e "${BLUE}步骤 1/4: 配置安装源${PLAIN}"
    echo -e " 1) 官方源 (适用于海外服务器)"
    echo -e " 2) 阿里云/清华源 (适用于中国大陆服务器)"
    read -p "请输入选项 [1-2] (默认2): " source_choice
    SOURCE_CHOICE=${source_choice:-2}

    echo -e "${YELLOW}正在安装必要依赖并配置仓库...${PLAIN}"
    
    if [ "$OS_RELEASE" == "centos" ]; then
        yum install -y yum-utils device-mapper-persistent-data lvm2
        if [ "$SOURCE_CHOICE" == "2" ]; then
            yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        else
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        fi
        # 刷新缓存以便能搜到版本
        yum makecache fast
    else
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings
        rm -f /etc/apt/keyrings/docker.gpg

        if [ "$SOURCE_CHOICE" == "2" ]; then
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/${OS_RELEASE}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/${OS_RELEASE} \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        else
            curl -fsSL https://download.docker.com/linux/${OS_RELEASE}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_RELEASE} \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        fi
        apt-get update
    fi
}

# 3. 选择 Docker 版本
select_docker_version() {
    echo -e "${BLUE}步骤 2/4: 选择 Docker Engine 版本${PLAIN}"
    echo -e "${YELLOW}正在获取可用版本列表...${PLAIN}"

    if [ "$OS_RELEASE" == "centos" ]; then
        # CentOS 列出版本
        yum list docker-ce --showduplicates | sort -r | head -n 20
        echo -e "\n${BLUE}上面列出了最新的 20 个版本。${PLAIN}"
        echo -e "例如: 3:24.0.7-1.el9"
    else
        # Debian/Ubuntu 列出版本
        apt-cache madison docker-ce | head -n 20
        echo -e "\n${BLUE}上面列出了最新的 20 个版本。${PLAIN}"
        echo -e "例如: 5:24.0.7-1~ubuntu.22.04~jammy"
    fi

    echo -e "------------------------------------------------"
    echo -e "请复制上方第二列的完整版本字符串 (Version String) 进行安装。"
    echo -e "如果不输入直接回车，将安装 ${GREEN}最新版本 (Latest)${PLAIN}。"
    read -p "请输入 Docker 版本字符串: " user_docker_ver

    DOCKER_VERSION=$user_docker_ver
}

# 4. 选择 Compose 版本
select_compose_version() {
    echo -e "${BLUE}步骤 3/4: 选择 Docker Compose 版本${PLAIN}"
    echo -e "Docker Compose V2 现在是 Docker 的插件 (docker-compose-plugin)。"
    echo -e " 1) 安装 Docker 官方仓库配套的最新版本 (推荐)"
    echo -e " 2) 指定版本 (将从 GitHub 下载指定版本的二进制文件)"
    read -p "请输入选项 [1-2] (默认1): " compose_choice
    
    if [[ "$compose_choice" == "2" ]]; then
        echo -e "请输入需要的版本号 (例如 v2.24.0 ): "
        read -p "版本号: " user_compose_ver
        if [[ -z "$user_compose_ver" ]]; then
             echo -e "${YELLOW}未输入版本号，将使用默认源安装。${PLAIN}"
        else
             COMPOSE_VERSION=$user_compose_ver
        fi
    fi
}

# 5. 执行安装
install_process() {
    echo -e "${YELLOW}开始安装...${PLAIN}"
    
    # 安装 Docker Engine
    if [ "$OS_RELEASE" == "centos" ]; then
        if [[ -z "$DOCKER_VERSION" ]]; then
            yum install -y docker-ce docker-ce-cli containerd.io
        else
            # CentOS 需要特定语法安装版本，通常 docker-ce-cli 也需要匹配
            # 这里简化处理，尝试安装指定版本的 package
            # 注意：CentOS 版本字符串通常包含 epoch (3:)，yum install 需要完整的名字
            yum install -y docker-ce-"$DOCKER_VERSION" docker-ce-cli-"$DOCKER_VERSION" containerd.io
        fi
    else
        if [[ -z "$DOCKER_VERSION" ]]; then
            apt-get install -y docker-ce docker-ce-cli containerd.io
        else
            apt-get install -y docker-ce="$DOCKER_VERSION" docker-ce-cli="$DOCKER_VERSION" containerd.io
        fi
    fi

    # 安装 Docker Compose
    if [[ -z "$COMPOSE_VERSION" ]]; then
        # 使用源中的插件
        if [ "$OS_RELEASE" == "centos" ]; then
            yum install -y docker-compose-plugin
        else
            apt-get install -y docker-compose-plugin
        fi
    else
        # 下载指定二进制
        echo -e "${YELLOW}正在下载 Docker Compose $COMPOSE_VERSION ...${PLAIN}"
        mkdir -p /usr/local/lib/docker/cli-plugins
        # 判断下载源，如果之前选了国内源，这里尝试用代理（可选，这里默认 GitHub）
        # 为了稳定性，这里使用官方 GitHub release
        curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi

    systemctl start docker
    systemctl enable docker
}

# 6. 后置配置 (镜像加速、日志、用户)
post_config() {
    echo -e "${BLUE}步骤 4/4: 后置优化配置${PLAIN}"
    
    # 镜像加速
    echo -e "${BLUE}是否配置国内镜像加速器 (Registry Mirrors)?${PLAIN}"
    read -p "是否配置? [y/n] (默认y): " config_mirror
    config_mirror=${config_mirror:-y}

    local mirrors_json=""
    if [[ "$config_mirror" == "y" ]]; then
        mirrors_json='"registry-mirrors": [
        "https://docker.m.daocloud.io",
        "https://dockerproxy.com",
        "https://mirror.baidubce.com",
        "https://docker.nju.edu.cn"
    ],'
    fi

    # 日志轮转配置
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    ${mirrors_json}
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file": "3"
    }
}
EOF
    systemctl daemon-reload
    systemctl restart docker

    # 用户组配置
    echo -e "${BLUE}是否将当前用户 $(whoami) 加入 docker 组?${PLAIN}"
    read -p "输入用户名 (回车跳过): " docker_user
    if [[ -n "$docker_user" ]]; then
        usermod -aG docker $docker_user
        echo -e "${GREEN}用户 $docker_user 已添加。${PLAIN}"
    fi
}

# 7. Portainer 安装
install_portainer() {
    echo -e "${BLUE}是否安装 Portainer 图形化面板?${PLAIN}"
    read -p "[y/n] (默认n): " install_p
    install_p=${install_p:-n}
    
    if [[ "$install_p" == "y" ]]; then
        docker pull portainer/portainer-ce:latest
        docker run -d -p 8000:8000 -p 9000:9000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
        echo -e "${GREEN}Portainer 已启动: http://IP:9000${PLAIN}"
    fi
}

# 卸载功能
uninstall_all() {
    check_sys
    echo -e "${RED}警告：将卸载 Docker 及所有数据！${PLAIN}"
    read -p "确认? [y/N]: " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop docker
        if [ "$OS_RELEASE" == "centos" ]; then
            yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        else
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            apt-get autoremove -y
        fi
        rm -rf /var/lib/docker /etc/docker /usr/local/lib/docker/cli-plugins
        echo -e "${GREEN}卸载完成。${PLAIN}"
    fi
}

# 主流程
main() {
    clear
    echo -e "================================================="
    echo -e "   Docker 高级安装脚本 (支持版本选择)"
    echo -e "================================================="
    echo -e " 1. 安装 Docker (可自选版本)"
    echo -e " 2. 卸载 Docker"
    echo -e " 0. 退出"
    echo -e "================================================="
    read -p "请输入选项: " choice

    case "$choice" in
        1)
            check_sys
            prepare_repo
            select_docker_version
            select_compose_version
            install_process
            post_config
            install_portainer
            echo -e "${GREEN}=========================================="
            echo -e " 安装全部完成！"
            echo -e " Docker 版本: $(docker -v)"
            echo -e " Compose 版本: $(docker compose version)"
            echo -e "==========================================${PLAIN}"
            ;;
        2)
            uninstall_all
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效输入"
            ;;
    esac
}

main
