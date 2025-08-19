#!/bin/bash

# Duix Face2Face 一键更新脚本
set -e

# 配置
IMAGE_NAME="duix-face2face-api"
FULL_IMAGE_NAME="image.ppinfra.com/prod-eftqrvyctuvyrddswevc/${IMAGE_NAME}:latest"

echo "🚀 开始更新 Duix Face2Face 服务..."

# 检查环境
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker未运行，请先启动Docker"
    exit 1
fi

if [ ! -f "Dockerfile" ]; then
    echo "❌ 请在项目目录中运行此脚本"
    exit 1
fi

# 构建和推送
echo "📦 构建镜像 (x86_64架构)..."
docker build --platform linux/amd64 --no-cache -t ${IMAGE_NAME} .

echo "🏷️ 标记镜像..."
docker tag ${IMAGE_NAME} ${FULL_IMAGE_NAME}

echo "⬆️ 推送镜像..."
docker push ${FULL_IMAGE_NAME}

echo "🧹 清理缓存..."
docker image prune -f > /dev/null 2>&1

# 完成提示
echo ""
echo "✅ 镜像更新完成！"
echo ""
echo "📋 接下来在PPIO实例中执行："
echo "   docker-compose -f docker-compose.cloud.yml pull"
echo "   docker-compose -f docker-compose.cloud.yml up -d"
echo ""
echo "🔗 PPIO控制台: https://ppio.com/gpu-instance/console"
