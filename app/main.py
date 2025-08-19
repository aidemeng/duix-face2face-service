"""
Duix Face2Face 云服务
基于FastAPI的纯Face2Face视频生成服务
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, HttpUrl
import requests
import os
import uuid
import time
import base64
import threading

from pathlib import Path
from typing import Optional, Dict, List
import logging

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Duix Face2Face Service",
    description="专注于Face2Face视频生成的云端API服务",
    version="1.0.0"
)

# 配置
DUIX_DATA_DIR = os.getenv("DUIX_DATA_DIR", "/code/data")
DUIX_INTERNAL_URL = os.getenv("DUIX_INTERNAL_URL", "http://localhost:8383")
CLEANUP_DELAY = int(os.getenv("CLEANUP_DELAY", "60"))  # 延迟清理时间(秒)
PERIODIC_CLEANUP_INTERVAL = int(os.getenv("PERIODIC_CLEANUP_INTERVAL", "300"))  # 定期清理间隔(秒)
MAX_FILE_AGE = int(os.getenv("MAX_FILE_AGE", "7200"))  # 文件最大存活时间(秒) - 2小时

class TaskSubmitRequest(BaseModel):
    audio_url: HttpUrl
    video_url: HttpUrl

class TaskSubmitResponse(BaseModel):
    success: bool
    task_code: Optional[str] = None
    error: Optional[str] = None

class TaskQueryRequest(BaseModel):
    task_code: str

class TaskResultRequest(BaseModel):
    result_filename: str  # 必需的结果文件名（从query接口获取）
    task_code: Optional[str] = None  # 可选的任务ID，用于更精确的文件清理

class TaskQueryResponse(BaseModel):
    success: bool
    code: Optional[int] = None
    data: Optional[dict] = None
    error: Optional[str] = None

class Face2FaceService:
    def __init__(self):
        self.duix_data_dir = DUIX_DATA_DIR
        self.duix_url = DUIX_INTERNAL_URL
        os.makedirs(self.duix_data_dir, exist_ok=True)

        # 任务文件映射表
        self.task_files: Dict[str, Dict[str, str]] = {}
        self.file_lock = threading.Lock()

        # 启动定期清理
        self.start_periodic_cleanup()
        logger.info(f"Face2Face服务启动，数据目录: {self.duix_data_dir}")
    
    def download_file(self, url: str, file_type: str) -> tuple[str, str]:
        """下载文件到Duix数据目录"""
        # 从URL中提取原始文件名
        from urllib.parse import urlparse
        import os.path

        parsed_url = urlparse(url)
        original_filename = os.path.basename(parsed_url.path)

        # 如果无法从URL获取文件名，生成默认文件名
        if not original_filename or '.' not in original_filename:
            ext = '.mp3' if file_type == 'audio' else '.mp4'
            filename = f"{int(time.time())}_{file_type}_{uuid.uuid4().hex[:8]}{ext}"
        else:
            filename = original_filename

        local_path = os.path.join(self.duix_data_dir, filename)
        container_path = f"/code/data/{filename}"

        logger.info(f"开始下载 {file_type}: {url}")

        try:
            response = requests.get(str(url), stream=True, timeout=120)
            response.raise_for_status()

            with open(local_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=1024*1024):
                    if chunk:
                        f.write(chunk)

            file_size = os.path.getsize(local_path)
            logger.info(f"下载完成: {local_path} ({file_size} bytes)")

            return container_path, local_path

        except Exception as e:
            # 下载失败时清理可能创建的部分文件
            if os.path.exists(local_path):
                try:
                    os.unlink(local_path)
                    logger.info(f"已清理失败文件: {local_path}")
                except Exception as cleanup_e:
                    logger.warning(f"清理失败文件时出错: {cleanup_e}")

            logger.error(f"下载失败 {url}: {e}")
            raise HTTPException(status_code=400, detail=f"文件下载失败: {str(e)}")
    
    def submit_task(self, audio_url: str, video_url: str) -> dict:
        """提交Face2Face任务，立即返回任务ID"""
        audio_local = None
        video_local = None
        task_code = None

        try:
            # 1. 下载文件
            logger.info("开始下载音频和视频文件")
            audio_container_path, audio_local = self.download_file(audio_url, 'audio')
            video_container_path, video_local = self.download_file(video_url, 'video')

            # 2. 调用Duix Face2Face
            task_code = str(uuid.uuid4())
            logger.info(f"提交Face2Face任务，任务ID: {task_code}")

            response = requests.post(f"{self.duix_url}/easy/submit", json={
                'audio_url': audio_container_path,
                'video_url': video_container_path,
                'code': task_code,
                'chaofen': 0,
                'watermark_switch': 0,
                'pn': 1
            })

            if response.status_code != 200:
                raise Exception(f"Duix API调用失败: {response.status_code} {response.text}")

            result = response.json()
            if result.get('code') != 10000:
                raise Exception(f"Duix任务提交失败: {result}")

            # 3. 记录任务文件映射关系
            with self.file_lock:
                self.task_files[task_code] = {
                    'audio_local': audio_local,
                    'video_local': video_local,
                    'created_time': time.time()
                }

            logger.info(f"任务提交成功: {task_code}")

            return {
                'success': True,
                'task_code': task_code
            }

        except Exception as e:
            # 提交失败时立即清理已下载的文件
            cleanup_files = [f for f in [audio_local, video_local] if f]
            if cleanup_files:
                self.cleanup_files(cleanup_files)

            # 如果已经创建了task_code但提交失败，清理映射记录
            if task_code:
                with self.file_lock:
                    self.task_files.pop(task_code, None)

            logger.error(f"任务提交失败: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    def query_task(self, task_code: str) -> dict:
        """查询任务状态"""
        try:
            logger.info(f"查询任务状态: {task_code}")

            response = requests.get(f"{self.duix_url}/easy/query?code={task_code}")
            if response.status_code != 200:
                raise Exception(f"查询API调用失败: {response.status_code} {response.text}")

            result = response.json()
            logger.debug(f"查询结果: {result}")

            return {
                'success': True,
                'code': result.get('code'),
                'data': result.get('data', {})
            }

        except Exception as e:
            logger.error(f"查询任务状态失败: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    def get_result(self, result_filename: str, task_code: str = None) -> dict:
        """获取任务结果并清理所有相关文件"""
        try:
            # 从 temp 子目录读取结果文件
            temp_dir = os.path.join(self.duix_data_dir, "temp")
            output_path = os.path.join(temp_dir, result_filename)

            logger.info(f"获取结果文件: {output_path}")

            if not os.path.exists(output_path):
                raise Exception(f"结果文件不存在: {result_filename}")

            # 读取结果
            with open(output_path, 'rb') as f:
                video_data = f.read()

            logger.info(f"获取结果成功，大小: {len(video_data)} bytes")

            # 使用任务文件映射表精确清理相关文件
            files_to_cleanup = [output_path]

            # 如果提供了task_code，从映射表中获取准确的输入文件路径
            if task_code:
                with self.file_lock:
                    task_info = self.task_files.get(task_code)
                    if task_info:
                        # 添加该任务的输入文件到清理列表
                        if task_info.get('audio_local'):
                            files_to_cleanup.append(task_info['audio_local'])
                        if task_info.get('video_local'):
                            files_to_cleanup.append(task_info['video_local'])

                        # 更新映射表，记录结果文件路径
                        task_info['result_file'] = output_path
                        task_info['result_retrieved_time'] = time.time()

                    else:
                        logger.warning(f"未找到任务 {task_code} 的文件映射")

            # 延迟清理所有文件和任务映射
            self.cleanup_files(files_to_cleanup, CLEANUP_DELAY)

            if task_code:
                self._schedule_task_cleanup(task_code)

            return {
                'success': True,
                'video_data': video_data,
                'size': len(video_data)
            }

        except Exception as e:
            logger.error(f"获取任务结果失败: {e}")
            raise HTTPException(status_code=500, detail=str(e))
    
    def cleanup_files(self, file_paths: List[str], delay: int = 0):
        """文件清理方法"""
        def do_cleanup():
            if delay > 0:
                time.sleep(delay)

            for file_path in file_paths:
                try:
                    if os.path.exists(file_path):
                        os.unlink(file_path)
                except Exception as e:
                    logger.warning(f"删除文件失败 {file_path}: {e}")

        if delay > 0:
            threading.Thread(target=do_cleanup, daemon=True).start()
        else:
            do_cleanup()

    def _schedule_task_cleanup(self, task_code: str):
        """延迟清理任务映射记录"""
        def cleanup_task_mapping():
            time.sleep(CLEANUP_DELAY + 10)
            with self.file_lock:
                self.task_files.pop(task_code, None)

        threading.Thread(target=cleanup_task_mapping, daemon=True).start()
    
    def start_periodic_cleanup(self):
        """启动定期清理"""
        def cleanup_worker():
            while True:
                try:
                    self.periodic_cleanup()
                    time.sleep(PERIODIC_CLEANUP_INTERVAL)
                except Exception as e:
                    logger.error(f"定期清理出错: {e}")
                    time.sleep(60)
        
        threading.Thread(target=cleanup_worker, daemon=True).start()
        logger.info("定期清理已启动")
    
    def periodic_cleanup(self):
        """智能定期清理：优先清理孤儿文件，保护活跃任务文件"""
        current_time = time.time()
        stats = {'orphan_files': 0, 'old_files': 0, 'expired_tasks': 0}

        try:
            # 获取当前活跃任务的所有文件路径
            active_files = set()
            with self.file_lock:
                for task_info in self.task_files.values():
                    for key in ['audio_local', 'video_local', 'result_file']:
                        if task_info.get(key):
                            active_files.add(task_info[key])

            # 智能清理文件
            for file_path in Path(self.duix_data_dir).iterdir():
                if not file_path.is_file():
                    continue

                file_str = str(file_path)
                file_age = current_time - file_path.stat().st_mtime

                # 分类清理策略
                should_delete = False

                if file_str not in active_files:
                    # 孤儿文件：不在任何活跃任务中
                    if file_age > CLEANUP_DELAY:
                        should_delete = True
                        stats['orphan_files'] += 1
                elif file_age > MAX_FILE_AGE:
                    # 活跃任务的过期文件
                    should_delete = True
                    stats['old_files'] += 1

                if should_delete:
                    try:
                        file_path.unlink()
                    except Exception as e:
                        logger.warning(f"清理文件失败 {file_path}: {e}")

            # 清理过期的任务映射记录
            with self.file_lock:
                expired_tasks = [
                    task_code for task_code, task_info in self.task_files.items()
                    if current_time - task_info.get('created_time', 0) > MAX_FILE_AGE
                ]

                for task_code in expired_tasks:
                    self.task_files.pop(task_code, None)
                    stats['expired_tasks'] += 1

            # 记录清理统计
            total_cleaned = sum(stats.values())
            if total_cleaned > 0:
                logger.info(f"定期清理: {total_cleaned} 项")

        except Exception as e:
            logger.error(f"定期清理出错: {e}")

    def get_task_files_info(self) -> Dict[str, Dict[str, str]]:
        """获取当前任务文件映射信息（用于调试）"""
        with self.file_lock:
            return dict(self.task_files)

# 全局服务实例
face2face_service = Face2FaceService()

@app.get("/")
async def root():
    """根路径"""
    return {
        "service": "Duix Face2Face Service",
        "version": "1.0.0",
        "status": "running"
    }

@app.get("/health")
async def health_check():
    """健康检查"""
    return {
        "status": "healthy",
        "data_dir": face2face_service.duix_data_dir,
        "data_dir_exists": os.path.exists(face2face_service.duix_data_dir),
        "active_tasks": len(face2face_service.task_files),
        "timestamp": time.time()
    }

@app.get("/debug/tasks")
async def debug_tasks():
    """调试接口：查看任务状态"""
    task_files = face2face_service.get_task_files_info()

    try:
        files_count = len(list(Path(face2face_service.duix_data_dir).glob("*")))
    except Exception:
        files_count = -1

    return {
        "active_tasks": len(task_files),
        "files_in_dir": files_count,
        "task_files": task_files
    }

@app.post("/api/submit_task", response_model=TaskSubmitResponse)
async def submit_task(request: TaskSubmitRequest):
    """
    提交Face2Face任务

    - audio_url: 音频文件URL (支持WAV/MP3等格式)
    - video_url: 人物参考视频URL (MP4格式)

    返回任务ID，需要后续轮询查询状态
    """
    try:
        result = face2face_service.submit_task(
            str(request.audio_url),
            str(request.video_url)
        )

        return TaskSubmitResponse(
            success=True,
            task_code=result['task_code']
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"任务提交API出错: {e}")
        return TaskSubmitResponse(
            success=False,
            error=str(e)
        )

@app.get("/api/query_task", response_model=TaskQueryResponse)
async def query_task(task_code: str):
    """
    查询任务状态

    - task_code: 任务ID

    返回任务状态信息
    """
    try:
        result = face2face_service.query_task(task_code)

        return TaskQueryResponse(
            success=True,
            code=result['code'],
            data=result['data']
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"任务查询API出错: {e}")
        return TaskQueryResponse(
            success=False,
            error=str(e)
        )

@app.get("/api/get_result")
async def get_result(filename: str, task_code: str = None):
    """
    获取任务结果

    - filename: 结果文件名
    - task_code: 任务ID

    返回base64编码的生成视频
    """
    try:
        result = face2face_service.get_result(
            filename,
            task_code
        )

        return {
            "success": True,
            "video_data": base64.b64encode(result['video_data']).decode(),
            "size": result['size'],
            "format": "mp4"
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取结果API出错: {e}")
        return {
            "success": False,
            "error": str(e)
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8385)
