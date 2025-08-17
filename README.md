# Duix Face2Face 云服务

基于FastAPI的专业Face2Face视频生成云端API服务，专注于数字人口型同步视频生成。

## 🎯 服务特点

- **专注核心功能**: 只做Face2Face视频生成，不包含用户管理、模版管理等业务逻辑
- **无状态设计**: 每次请求独立处理，不依赖本地数据库
- **自动清理**: 智能的文件清理机制，防止磁盘空间占满
- **高性能**: 基于FastAPI的异步处理
- **易于集成**: 标准的REST API接口

## 🏗️ 架构设计

```
外部请求 → FastAPI服务 → 原始Duix AI服务 → 返回结果
    ↓           ↓              ↓           ↓
  HTTP API   文件下载管理    Face2Face计算   视频数据
```

## 🚀 快速开始

### 1. 环境要求

- Docker & Docker Compose
- NVIDIA GPU + CUDA支持
- 至少8GB显存

### 2. 启动服务

```bash
# 克隆项目
git clone <your-repo>
cd duix-face2face-service

# 创建数据目录
mkdir -p data

# 启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f duix-face2face-api
```

### 3. 健康检查

```bash
# 检查服务状态
curl http://localhost:8385/health

# 预期返回
{
  "status": "healthy",
  "data_dir": "/code/data",
  "data_dir_exists": true,
  "timestamp": 1703123456.789
}
```

## 📖 API文档

### 生成视频

**POST** `/api/generate_video`

**请求体:**
```json
{
  "audio_url": "https://your-oss.com/audio.wav",
  "video_url": "https://your-oss.com/reference_video.mp4"
}
```

**响应:**
```json
{
  "success": true,
  "video_data": "base64编码的视频数据",
  "size": 1234567,
  "format": "mp4"
}
```

**错误响应:**
```json
{
  "success": false,
  "error": "错误描述"
}
```

### 健康检查

**GET** `/health`

返回服务健康状态和基本信息。

## 🔧 配置说明

### 环境变量

- `DUIX_INTERNAL_URL`: 内部Duix服务地址 (默认: http://localhost:8383)
- `DUIX_DATA_DIR`: 数据目录路径 (默认: /code/data)

### 清理配置

- `CLEANUP_DELAY`: 延迟清理时间，默认60秒
- `PERIODIC_CLEANUP_INTERVAL`: 定期清理间隔，默认300秒
- `MAX_FILE_AGE`: 文件最大存活时间，默认3600秒

## 🛠️ 开发模式

```bash
# 安装依赖
pip install -r requirements.txt

# 启动开发服务器
uvicorn app.main:app --reload --host 0.0.0.0 --port 8385

# 访问API文档
open http://localhost:8385/docs
```

## 📊 监控和日志

### 查看日志
```bash
# 查看API服务日志
docker-compose logs -f duix-face2face-api

# 查看Duix服务日志
docker-compose logs -f heygem-gen-video
```

### 监控指标
- 服务健康状态: `/health`
- 文件清理统计: 查看日志中的清理记录
- 处理时间: 查看日志中的任务耗时

## 🔒 安全考虑

1. **文件隔离**: 每次请求使用独立的临时文件
2. **自动清理**: 防止敏感文件长期存储
3. **超时控制**: 避免长时间占用资源
4. **错误处理**: 完善的异常处理和资源清理

## 🚀 生产部署

### 性能优化
- 调整worker数量: `--workers 4`
- 配置资源限制: 在docker-compose.yml中设置内存和CPU限制
- 使用负载均衡: 部署多个实例

### 监控告警
- 集成Prometheus监控
- 配置日志收集
- 设置磁盘空间告警

## 🤝 集成示例

### Python客户端
```python
import requests
import base64

def generate_avatar_video(audio_url: str, video_url: str) -> bytes:
    response = requests.post("http://your-server:8385/api/generate_video", json={
        "audio_url": audio_url,
        "video_url": video_url
    })
    
    result = response.json()
    if result["success"]:
        return base64.b64decode(result["video_data"])
    else:
        raise Exception(result["error"])
```

### 在您的media-content-hub中集成
```python
class DuixFace2FaceService:
    def __init__(self):
        self.duix_url = "http://duix-server:8385"
    
    async def generate_video(self, audio_url: str, video_url: str) -> bytes:
        response = requests.post(f"{self.duix_url}/api/generate_video", json={
            "audio_url": audio_url,
            "video_url": video_url
        })
        
        result = response.json()
        if result["success"]:
            return base64.b64decode(result["video_data"])
        else:
            raise Exception(result["error"])
```

## 📝 更新日志

### v1.0.0
- 初始版本
- 基础Face2Face视频生成功能
- 自动文件清理机制
- FastAPI框架集成
