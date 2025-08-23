#!/bin/bash

# Duix Face2Face 服务部署脚本 - Linux环境
set -e

echo "🚀 开始部署 Duix Face2Face 服务 (Linux环境)..."

# 检查系统
echo "📋 系统信息:"
uname -a
echo ""

# 检查Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker未安装"
    echo "💡 安装命令:"
    echo "   Ubuntu/Debian: sudo apt-get update && sudo apt-get install docker.io"
    echo "   CentOS/RHEL: sudo yum install docker"
    exit 1
fi

# 检查Docker服务状态
if ! sudo docker info > /dev/null 2>&1; then
    echo "❌ Docker未运行，尝试启动..."
    sudo systemctl start docker
    sudo systemctl enable docker
    sleep 3

    if ! sudo docker info > /dev/null 2>&1; then
        echo "❌ Docker启动失败，请手动启动: sudo systemctl start docker"
        exit 1
    fi
fi

# 检查docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose未安装"
    echo "💡 安装命令:"
    echo "   sudo curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
    echo "   sudo chmod +x /usr/local/bin/docker-compose"
    exit 1
fi

# 检查Git
if ! command -v git &> /dev/null; then
    echo "❌ Git未安装"
    echo "💡 安装命令:"
    echo "   Ubuntu/Debian: sudo apt-get install git"
    echo "   CentOS/RHEL: sudo yum install git"
    exit 1
fi

echo "✅ 环境检查通过"

# 克隆代码
echo "📦 克隆项目代码..."
if [ -d "duix-face2face-service" ]; then
    echo "📁 项目目录已存在，更新代码..."
    cd duix-face2face-service
    git pull
else
    git clone https://github.com/aidemeng/duix-face2face-service.git
    cd duix-face2face-service
fi

echo "✅ 代码准备完成"

# 检查NVIDIA Docker支持 (如果有GPU)
if command -v nvidia-smi &> /dev/null; then
    echo "🎮 检测到NVIDIA GPU"
    if ! command -v nvidia-docker &> /dev/null && ! docker info | grep -q nvidia; then
        echo "⚠️ 未检测到NVIDIA Docker支持，GPU功能可能不可用"
        echo "💡 安装NVIDIA Docker: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    else
        echo "✅ NVIDIA Docker支持已启用"
    fi
fi

# 启动服务
echo "🐳 启动Docker服务..."
sudo docker-compose up -d

echo "⏳ 等待服务启动..."
sleep 15

echo "🔍 检查服务状态..."
sudo docker-compose ps

# 检查端口占用
echo "🔌 检查端口状态..."
if netstat -tuln 2>/dev/null | grep -q ":8383"; then
    echo "✅ 端口 8383 已监听"
else
    echo "⚠️ 端口 8383 未监听"
fi

if netstat -tuln 2>/dev/null | grep -q ":8385"; then
    echo "✅ 端口 8385 已监听"
else
    echo "⚠️ 端口 8385 未监听"
fi

echo ""
echo "✅ 部署完成！"
echo ""
echo "🎯 服务地址:"
echo "🤖 AI服务: http://localhost:8383"
echo "🌐 API服务: http://localhost:8385"
echo "📊 健康检查: http://localhost:8385/health"
echo ""
echo "🔧 管理命令:"
echo "  查看日志: sudo docker-compose logs -f"
echo "  停止服务: sudo docker-compose down"
echo "  重启服务: sudo docker-compose restart"
echo "  查看状态: sudo docker-compose ps"
echo ""
echo "🔥 防火墙提醒:"
echo "  如果无法访问服务，请检查防火墙设置:"
echo "  Ubuntu/Debian: sudo ufw allow 8383 && sudo ufw allow 8385"
echo "  CentOS/RHEL: sudo firewall-cmd --add-port=8383/tcp --permanent && sudo firewall-cmd --add-port=8385/tcp --permanent && sudo firewall-cmd --reload"
