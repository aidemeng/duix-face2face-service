#!/bin/bash

# Linux环境依赖安装脚本
set -e

echo "🔧 开始安装 Duix Face2Face 服务依赖..."

# 检测Linux发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    echo "❌ 无法检测Linux发行版"
    exit 1
fi

echo "📋 检测到系统: $OS $VER"

# 更新包管理器
echo "📦 更新包管理器..."
if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
    sudo apt-get update
elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
    sudo yum update -y
elif [[ "$OS" == *"Fedora"* ]]; then
    sudo dnf update -y
else
    echo "⚠️ 未识别的Linux发行版，请手动安装依赖"
fi

# 安装基础工具
echo "🛠️ 安装基础工具..."
if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
    sudo apt-get install -y curl wget git net-tools
elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
    sudo yum install -y curl wget git net-tools
elif [[ "$OS" == *"Fedora"* ]]; then
    sudo dnf install -y curl wget git net-tools
fi

# 安装Docker
echo "🐳 安装Docker..."
if ! command -v docker &> /dev/null; then
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        # Ubuntu/Debian Docker安装
        sudo apt-get install -y apt-transport-https ca-certificates gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        # CentOS/RHEL Docker安装
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io
    elif [[ "$OS" == *"Fedora"* ]]; then
        # Fedora Docker安装
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    fi
    
    # 启动Docker服务
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # 添加当前用户到docker组
    sudo usermod -aG docker $USER
    echo "⚠️ 请重新登录以使docker组权限生效，或运行: newgrp docker"
else
    echo "✅ Docker已安装"
fi

# 安装docker-compose
echo "🔧 安装docker-compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
    echo "✅ docker-compose已安装"
fi

# 检查NVIDIA驱动和Docker支持
if command -v nvidia-smi &> /dev/null; then
    echo "🎮 检测到NVIDIA GPU，安装NVIDIA Docker支持..."
    
    # 安装NVIDIA Container Toolkit
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
        sudo apt-get update
        sudo apt-get install -y nvidia-docker2
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | sudo tee /etc/yum.repos.d/nvidia-docker.repo
        sudo yum install -y nvidia-docker2
    fi
    
    # 重启Docker服务
    sudo systemctl restart docker
    echo "✅ NVIDIA Docker支持已安装"
else
    echo "ℹ️ 未检测到NVIDIA GPU，跳过GPU支持安装"
fi

# 配置防火墙
echo "🔥 配置防火墙..."
if command -v ufw &> /dev/null; then
    # Ubuntu/Debian UFW
    sudo ufw allow 8383/tcp
    sudo ufw allow 8385/tcp
    echo "✅ UFW防火墙规则已添加"
elif command -v firewall-cmd &> /dev/null; then
    # CentOS/RHEL firewalld
    sudo firewall-cmd --add-port=8383/tcp --permanent
    sudo firewall-cmd --add-port=8385/tcp --permanent
    sudo firewall-cmd --reload
    echo "✅ firewalld防火墙规则已添加"
else
    echo "⚠️ 未检测到防火墙管理工具，请手动开放端口 8383 和 8385"
fi

echo ""
echo "✅ 依赖安装完成！"
echo ""
echo "📋 安装的组件:"
echo "  ✅ Docker $(docker --version 2>/dev/null || echo '未安装')"
echo "  ✅ docker-compose $(docker-compose --version 2>/dev/null || echo '未安装')"
echo "  ✅ Git $(git --version 2>/dev/null || echo '未安装')"
echo ""
echo "🚀 现在可以运行部署脚本:"
echo "  ./deploy.sh"
echo ""
echo "⚠️ 如果添加了docker用户组，请重新登录或运行: newgrp docker"
