"""
Video Analysis Web API
FastAPI service for video content analysis
"""

from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from typing import Optional
import tempfile
import os
import json
from utils.main import process_video

app = FastAPI(
    title="Video Analyzer API",
    description="AI-powered video content analysis with keyframe extraction and audio analysis",
    version="1.0.0",
    swagger_ui_parameters={"defaultModelsExpandDepth": -1}
)

class VideoAnalysisRequest(BaseModel):
    """Video analysis request model for URL/blob path"""
    video_url: str
    system_prompt: Optional[str] = None
    user_prompt: Optional[str] = None
    enable_audio_analysis: bool = False
    # Extraction parameters
    max_frames: Optional[int] = 12
    min_time_gap: Optional[float] = 0.8
    enable_image_enhancement: Optional[bool] = False
    min_frames_after_dedup: Optional[int] = 3
    frame_gap: Optional[int] = 5
    motion_weight: Optional[float] = 3.0
    scene_weight: Optional[float] = 1.5
    color_weight: Optional[float] = 0.5
    edge_weight: Optional[float] = 2.0
    content_frame_bar: Optional[float] = 0.5
    enable_deduplication: Optional[bool] = True
    similarity_threshold: Optional[float] = 0.95
    maximum_dimension: Optional[int] = 480
    # Audio parameters
    audio_enable_v2: bool = False
    audio_enable_v3: bool = False
    audio_prompt: Optional[str] = None

@app.get("/")
async def root():
    """Redirect to API documentation"""
    return RedirectResponse(url="/docs")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "video-analyzer"}

@app.post("/analyze-video-url")
async def analyze_video_from_url(request: VideoAnalysisRequest):
    """
    Analyze video from URL or Azure blob path
    
    Args:
        request: Video analysis request containing URL and parameters
        
    Returns:
        Analysis results including keyframes and content analysis
    """
    try:
        # Prepare extraction parameters
        extraction_params = {}
        if request.max_frames and request.max_frames is not None:
            extraction_params['max_frames'] = request.max_frames
        if request.min_time_gap and request.min_time_gap is not None:
            extraction_params['min_time_gap'] = request.min_time_gap
        if request.enable_image_enhancement and request.enable_image_enhancement is not None:
            extraction_params['enable_image_enhancement'] = request.enable_image_enhancement
        if request.min_frames_after_dedup and request.min_frames_after_dedup is not None:
            extraction_params['min_frames_after_dedup'] = request.min_frames_after_dedup
        if request.frame_gap and request.frame_gap is not None:
            extraction_params['frame_gap'] = request.frame_gap
        if request.motion_weight and request.motion_weight is not None:
            extraction_params['motion_weight'] = request.motion_weight
        if request.scene_weight and request.scene_weight is not None:
            extraction_params['scene_weight'] = request.scene_weight
        if request.color_weight and request.color_weight is not None:
            extraction_params['color_weight'] = request.color_weight
        if request.edge_weight and request.edge_weight is not None:
            extraction_params['edge_weight'] = request.edge_weight
        if request.content_frame_bar and request.content_frame_bar is not None:
            extraction_params['content_frame_bar'] = request.content_frame_bar
        if request.enable_deduplication and request.enable_deduplication is not None:
            extraction_params['enable_deduplication'] = request.enable_deduplication
        if request.similarity_threshold and request.similarity_threshold is not None:
            extraction_params['similarity_threshold'] = request.similarity_threshold
        if request.maximum_dimension and request.maximum_dimension is not None:
            extraction_params['maximum_dimension'] = request.maximum_dimension

        # Prepare audio configuration
        audio_config = {}
        if request.audio_enable_v2:
            audio_config['enable_v2'] = True
        if request.audio_enable_v3:
            audio_config['enable_v3'] = True
        if request.audio_prompt:
            audio_config['user_prompt'] = request.audio_prompt

        # Process video
        result = process_video(
            video_input=request.video_url,
            system_prompt=request.system_prompt,
            user_prompt=request.user_prompt,
            extraction_params=extraction_params,
            audio_config=audio_config,
            enable_audio_analysis=request.enable_audio_analysis
        )
        
        return result
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Video analysis failed: {str(e)}")

@app.post("/analyze-video-file")
async def analyze_video_file(
    file: UploadFile = File(..., description="Video file to analyze"),
    system_prompt: Optional[str] = Form(None, description="System prompt for analysis, send empty value to use default prompt."),
    user_prompt: Optional[str] = Form(None, description="User prompt for analysis send empty value to use default prompt."),
    enable_audio_analysis: bool = Form(False, description="Enable audio analysis, send empty value to use default value (False)."),
    max_frames: Optional[int] = Form(12, description="Maximum number of keyframes, send empty value to use default value (12)."),
    min_time_gap: Optional[float] = Form(0.8, description="Minimum time gap between frames, send empty value to use default value (0.8)."),
    enable_image_enhancement: Optional[bool] = Form(False, description="Enable image enhancement, send empty value to use default value (False)."),
    min_frames_after_dedup: Optional[int] = Form(3, description="Minimum frames to keep after deduplication, send empty value to use default value (3)."),
    frame_gap: Optional[int] = Form(5, description="Frame analysis interval, send empty value to use default value (5)."),
    motion_weight: Optional[float] = Form(3.0, description="Motion change weight, send empty value to use default value (3.0)."),
    scene_weight: Optional[float] = Form(1.5, description="Scene change weight, send empty value to use default value (1.5)."),
    color_weight: Optional[float] = Form(0.5, description="Color change weight, send empty value to use default value (0.5)."),
    edge_weight: Optional[float] = Form(2.0, description="Edge change weight, send empty value to use default value (2.0)."),
    content_frame_bar: Optional[float] = Form(0.5, description="Content frame selection ratio (between 0-1, indicating the proportion selected from candidate frames), send empty value to use default value (0.5)."),
    enable_deduplication: Optional[bool] = Form(True, description="Enable deduplication, send empty value to use default value (True)."),
    similarity_threshold: Optional[float] = Form(0.95, description="Similarity threshold, send empty value to use default value (0.95)."),
    maximum_dimension: Optional[int] = Form(480, description="Maximum dimension limit, send empty value to use default value (480)."),
    audio_enable_v2: bool = Form(False, description="Enable V2 audio model, send empty value to use default value (False)."),
    audio_enable_v3: bool = Form(False, description="Enable V3 audio model, send empty value to use default value (False)."),
    audio_prompt: Optional[str] = Form(None, description="Audio analysis prompt, send empty value to use default prompt.")
):
    """
    Upload and analyze video file
    
    Args:
        file: Uploaded video file
        Other parameters: Analysis configuration options
        
    Returns:
        Analysis results including keyframes and content analysis
    """
    temp_path = None
    try:
        # Validate file type
        if not file.content_type or not file.content_type.startswith('video/'):
            raise HTTPException(status_code=400, detail="Please upload a valid video file")
        
        # Save uploaded file to temporary directory
        file_extension = os.path.splitext(file.filename)[1] if file.filename else '.mp4'
        with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as tmp_file:
            content = await file.read()
            tmp_file.write(content)
            temp_path = tmp_file.name
        
        # Prepare extraction parameters
        extraction_params = {}
        if max_frames is not None:
            extraction_params['max_frames'] = max_frames
        if min_time_gap is not None:
            extraction_params['min_time_gap'] = min_time_gap
        if enable_image_enhancement is not None:
            extraction_params['enable_image_enhancement'] = enable_image_enhancement
        if min_frames_after_dedup is not None:  
            extraction_params['min_frames_after_dedup'] = min_frames_after_dedup
        if frame_gap is not None:
            extraction_params['frame_gap'] = frame_gap
        if motion_weight is not None:
            extraction_params['motion_weight'] = motion_weight
        if scene_weight is not None:
            extraction_params['scene_weight'] = scene_weight
        if color_weight is not None:
            extraction_params['color_weight'] = color_weight
        if edge_weight is not None:
            extraction_params['edge_weight'] = edge_weight
        if content_frame_bar is not None:
            extraction_params['content_frame_bar'] = content_frame_bar
        if enable_deduplication is not None:
            extraction_params['enable_deduplication'] = enable_deduplication
        if similarity_threshold is not None:
            extraction_params['similarity_threshold'] = similarity_threshold
        if maximum_dimension is not None:
            extraction_params['maximum_dimension'] = maximum_dimension

        # Prepare audio configuration
        audio_config = {}
        if audio_enable_v2:
            audio_config['enable_v2'] = True
        if audio_enable_v3:
            audio_config['enable_v3'] = True
        if audio_prompt:
            audio_config['user_prompt'] = audio_prompt
            
        # Process video
        result = process_video(
            video_input=temp_path,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            extraction_params=extraction_params,
            audio_config=audio_config,
            enable_audio_analysis=enable_audio_analysis,
            cleanup_temp=False  # We'll clean up manually
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Video analysis failed: {str(e)}")
    finally:
        # Clean up temporary file
        if temp_path and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except Exception as cleanup_error:
                print(f"Warning: Failed to clean up temporary file: {cleanup_error}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)