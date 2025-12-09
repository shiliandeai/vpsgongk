#!/bin/bash

# =======================================================================
# Docker 自动安装脚本 (全版本列表版)
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
echo -e "\n${BLUE}>>> 正在清理旧版本...${NC}"
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

# 4. 安装依赖并配置仓库 (这是获取版本列表的前提)
echo -e "\n${BLUE}>>> 正在配置仓库环境...${NC}"
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

# 5. 版本选择 (逻辑升级)
echo -e "\n${BLUE}>>> 选择 Docker 版本：${NC}"
echo "1) 自动安装最新版 (Latest) [默认]"
echo "2) 选择特定版本 (列出所有可用版本)"
read -p "请输入选项: " VER_OPT
VER_OPT=${VER_OPT:-1}

TARGET_VERSION=""

if [ "$VER_OPT" == "2" ]; then
    echo -e "${YELLOW}正在从仓库获取全量版本列表，可能需要几秒钟...${NC}"
    
    # 定义数组
    declare -a VERSION_LIST
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        # apt-cache madison 本身通常是按版本降序排列的，但我们强制 awk 提取并确保格式
        # 去掉 head -n 限制，获取全部
        RAW_LIST=$(apt-cache madison docker-ce | awk '{print $3}')
        
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
        # yum list 输出较乱，需要严格过滤和排序
        # sort -V -r : 按版本号(Version)进行逆序(Reverse)排序，即由新到旧
        RAW_LIST=$(yum list docker-ce --showduplicates | grep "docker-ce" | awk '{print $2}' | sort -V -r)
    fi

    # 转为数组
    i=1
    for v in $RAW_LIST; do
        VERSION_LIST[$i]=$v
        ((i++))
    done

    # 检查是否有版本
    if [ ${#VERSION_LIST[@]} -eq 0 ]; then
        echo -e "${RED}未获取到任何版本信息，请检查网络或源配置。${NC}"
        exit 1
    fi

    echo -e "\n${BLUE}====== 可用版本列表 (按时间/版本倒序) ======${NC}"
    echo -e "${YELLOW}序号\t版本号${NC}"
    
    # 打印所有版本
    for idx in "${!VERSION_LIST[@]}"; do
        echo -e "$idx)\t${VERSION_LIST[$idx]}"
    done
    echo -e "${BLUE}==============================================${NC}"
    
    # 交互选择
    while true; do
        read -p "请输入要安装的版本对应的 [数字序号]: " V_INDEX
        # 检查输入是否为数字
        if [[ "$V_INDEX" =~ ^[0-9]+$ ]]; then
            if [ -n "${VERSION_LIST[$V_INDEX]}" ]; then
                TARGET_VERSION="${VERSION_LIST[$V_INDEX]}"
                echo -e "${GREEN}>>> 您已选择: $TARGET_VERSION${NC}"
                break
            else
                echo -e "${RED}序号不存在，请重新输入。${NC}"
            fi
        else
            echo -e "${RED}请输入有效的数字。${NC}"
        fi
    done
fi

# 6. 执行安装
echo -e "\n${BLUE}>>> 开始安装...${NC}"
PKG_NAME=""
if [ -z "$TARGET_VERSION" ]; then
    PKG_NAME="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
else
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        PKG_NAME="docker-ce=$TARGET_VERSION docker-ce-cli=$TARGET_VERSION containerd.io docker-buildx-plugin docker-compose-plugin"
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
        # CentOS 有时版本字符串带 epoch (如 3:20.10.x)，直接拼接即可
        PKG_NAME="docker-ce-$TARGET_VERSION docker-ce-cli-$TARGET_VERSION containerd.io docker-buildx-plugin docker-compose-plugin"
    fi
fi

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y $PKG_NAME
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "alinux" ]]; then
    yum install -y $PKG_NAME
fi

# 7. 启动与配置
echo -e "\n${BLUE}>>> 配置服务...${NC}"
systemctl start docker
systemctl enable docker

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Docker 安装成功！${NC}"
echo -e "${GREEN}========================================${NC}"
docker --version

echo -e "\n${YELLOW}提示：非 root 用户请执行: sudo usermod -aG docker \$USER && newgrp docker${NC}"
