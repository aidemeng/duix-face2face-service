#!/bin/bash

# Duix Face2Face 服务调试启动脚本

echo "🚀 启动 Duix Face2Face 服务..."

# 检查 GPU 状态
echo "📊 检查 GPU 状态..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
else
    echo "⚠️  nvidia-smi 不可用，请确认 GPU 驱动已安装"
fi

# 停止现有服务
echo "🛑 停止现有服务..."
docker-compose -f docker-compose.yml down

# 清理旧容器和网络
echo "🧹 清理资源..."
docker system prune -f

# 启动服务
echo "🐳 启动服务..."
docker-compose -f docker-compose.yml up -d

# 等待服务启动
echo "⏳ 等待服务启动..."
sleep 10

# 检查服务状态
echo "🔍 检查服务状态..."
docker-compose -f docker-compose.yml ps

# 检查健康状态
echo "💊 检查健康状态..."
echo "heygem-gen-video 健康检查:"
docker inspect heygem-gen-video --format='{{.State.Health.Status}}'

echo "duix-face2face-api 健康检查:"
docker inspect duix-face2face-api --format='{{.State.Health.Status}}'

# 显示日志
echo "📋 显示最近日志..."
echo "=== heygem-gen-video 日志 ==="
docker-compose -f docker-compose.yml logs --tail=20 heygem-gen-video

echo "=== duix-face2face-api 日志 ==="
docker-compose -f docker-compose.yml logs --tail=20 duix-face2face-api

# 测试连接
echo "🧪 测试服务连接..."
echo "测试 heygem-gen-video (8383):"
curl -s http://localhost:8383/health || echo "❌ heygem-gen-video 不可达"

echo "测试 duix-face2face-api (8385):"
curl -s http://localhost:8385/health || echo "❌ duix-face2face-api 不可达"

# 测试内部连接
echo "🔗 测试容器间连接..."
docker exec duix-face2face-api curl -s http://heygem-gen-video:8383/health || echo "❌ 容器间连接失败"

echo "✅ 调试完成！"
echo ""
echo "📡 服务地址:"
echo "  - heygem-gen-video: http://localhost:8383"
echo "  - duix-face2face-api: http://localhost:8385"
echo ""
echo "📊 监控命令:"
echo "  - 查看日志: docker-compose -f docker-compose.yml logs -f"
echo "  - 查看状态: docker-compose -f docker-compose.yml ps"
echo "  - 重启服务: docker-compose -f docker-compose.yml restart"
