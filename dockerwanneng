#!/bin/bash

# =======================================================================
# Docker 自动安装脚本 (优化版)
# 功能：源选择、版本数字选择、环境清理、自动配置
# =======================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查 Root 权限
if [ $(id -u) -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 权限运行 (sudo ./install_docker.sh)${NC}"
    exit 1
fi

# 1. 系统检测
echo -e "${BLUE}>>> 正在检测操作系统...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}无法识别操作系统，脚本退出。${NC}"
    exit 1
fi
echo -e "${GREEN}系统识别为: $OS $VERSION_ID${NC}"

# 2. 卸载旧版本
echo -e "\n${BLUE}>>> 正在清理旧版本 (如果存在)...${NC}"
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get remove -y docker docker-engine docker.io containerd runc &> /dev/null
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine &> /dev/null
fi
echo -e "${GREEN}清理完成。${NC}"

# 3. 配置镜像源
echo -e "\n${BLUE}>>> 选择下载源：${NC}"
echo "1) 阿里云 (推荐国内)"
echo "2) 清华大学"
echo "3) 官方源 (推荐国外)"
read -p "请输入选项 [默认: 1]: " MIRROR
MIRROR=${MIRROR:-1}

case $MIRROR in
    1) BASE_URL="https://mirrors.aliyun.com/docker-ce"; NAME="阿里云";;
    2) BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"; NAME="清华源";;
    3) BASE_URL="https://download.docker.com"; NAME="官方源";;
    *) BASE_URL="https://mirrors.aliyun.com/docker-ce"; NAME="阿里云";;
esac
echo -e "${YELLOW}已选择：$NAME${NC}"

# 4. 安装依赖与仓库配置
echo -e "\n${BLUE}>>> 安装依赖并配置仓库...${NC}"
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg
    curl -fsSL "$BASE_URL/linux/$OS/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $BASE_URL/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
    yum install -y yum-utils
    yum-config-manager --add-repo $BASE_URL/linux/centos/docker-ce.repo
    if [ "$MIRROR" != "3" ]; then
        sed -i "s|https://download.docker.com|$BASE_URL|g" /etc/yum.repos.d/docker-ce.repo
    fi
    yum makecache
fi

# 5. 版本选择 (核心优化部分)
echo -e "\n${BLUE}>>> 选择 Docker 版本：${NC}"
echo "1) 自动安装最新版 (Latest) [默认]"
echo "2) 选择特定版本"
read -p "请输入选项: " VER_OPT
VER_OPT=${VER_OPT:-1}

TARGET_VERSION=""

if [ "$VER_OPT" == "2" ]; then
    echo -e "${YELLOW}正在获取可用版本列表，请稍候...${NC}"
    
    # 定义数组存储版本
    declare -a VERSION_LIST
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        # 获取 raw 数据，并逐行读入数组 (取前15个)
        RAW_LIST=$(apt-cache madison docker-ce | head -n 15 | awk '{print $3}')
        
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
        # CentOS 输出处理，排除 header，取版本列
        RAW_LIST=$(yum list docker-ce --showduplicates | sort -r | grep "docker-ce" | head -n 15 | awk '{print $2}')
    fi

    # 将 RAW_LIST 转为数组
    i=1
    for v in $RAW_LIST; do
        VERSION_LIST[$i]=$v
        ((i++))
    done

    # 打印菜单
    echo -e "\n${BLUE}可用版本列表：${NC}"
    for idx in "${!VERSION_LIST[@]}"; do
        echo "$idx) ${VERSION_LIST[$idx]}"
    done
    
    # 用户输入
    while true; do
        read -p "请输入对应数字序号: " V_INDEX
        if [ -n "${VERSION_LIST[$V_INDEX]}" ]; then
            TARGET_VERSION="${VERSION_LIST[$V_INDEX]}"
            echo -e "${GREEN}您选择了版本: $TARGET_VERSION${NC}"
            break
        else
            echo -e "${RED}输入无效，请重新输入数字序号。${NC}"
        fi
    done
fi

# 6. 执行安装
echo -e "\n${BLUE}>>> 开始安装 Docker...${NC}"
PKG_NAME=""
if [ -z "$TARGET_VERSION" ]; then
    # 安装最新
    PKG_NAME="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
else
    # 安装指定版本
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        # Ubuntu/Debian 格式: package=version
        PKG_NAME="docker-ce=$TARGET_VERSION docker-ce-cli=$TARGET_VERSION containerd.io docker-buildx-plugin docker-compose-plugin"
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
        # CentOS 格式: package-version (注意有时版本号带 epoch 如 3:xxx，yum 通常能智能处理，或者只需版本号部分)
        # 简单处理：直接拼接完整字符串
        PKG_NAME="docker-ce-$TARGET_VERSION docker-ce-cli-$TARGET_VERSION containerd.io docker-buildx-plugin docker-compose-plugin"
    fi
fi

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y $PKG_NAME
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
    yum install -y $PKG_NAME
fi

# 7. 启动与配置
echo -e "\n${BLUE}>>> 启动服务...${NC}"
systemctl start docker
systemctl enable docker

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Docker 安装成功！${NC}"
echo -e "${GREEN}========================================${NC}"
docker --version

echo -e "\n${YELLOW}提示：非 root 用户请执行: sudo usermod -aG docker \$USER && newgrp docker${NC}"
