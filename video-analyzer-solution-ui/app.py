from flask import Flask, render_template, request, jsonify, send_from_directory
import os
import time
import json
import base64
import gc
from werkzeug.utils import secure_filename
from utils.main import process_video
import uuid
import threading
import glob
from datetime import datetime, timedelta

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # 500MB max file size
app.config['UPLOAD_FOLDER'] = 'uploads'
os.environ['OPENCV_FFMPEG_LOGLEVEL'] = '-8'

# Ensure upload directories exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs('keyframes_output', exist_ok=True)
os.makedirs('audio_output', exist_ok=True)

# Allowed file extensions
ALLOWED_EXTENSIONS = {'mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv', 'webm', 'm4v'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/')
def index():
    return render_template('index.html')

def clean_old_files():
    """Clean files older than 100 minutes"""
    try:
        current_time = datetime.now()
        cutoff_time = current_time - timedelta(minutes=100)
        
        # Clean uploads and audio_output folders
        for folder in ['uploads', 'audio_output']:
            if os.path.exists(folder):
                for file_path in glob.glob(os.path.join(folder, '*')):
                    try:
                        file_time = datetime.fromtimestamp(os.path.getctime(file_path))
                        if file_time < cutoff_time:
                            os.remove(file_path)
                            print(f"Cleaned expired file: {file_path}")
                    except Exception as e:
                        print(f"Failed to clean file {file_path}: {e}")
    except Exception as e:
        print(f"File cleanup task failed: {e}")

def start_file_cleanup_timer():
    """Start file cleanup timer"""
    clean_old_files()  
    # Run cleanup every 10 minutes
    timer = threading.Timer(600.0, start_file_cleanup_timer)
    timer.daemon = True  # Set as daemon thread
    timer.start()

@app.route('/chat', methods=['POST'])
def chat():
    """Chat endpoint for video analysis"""
    filepath = None
    try:
        # Check if file was uploaded via FormData
        if 'video' in request.files:
            # File upload mode
            file = request.files['video']
            user_prompt = request.form.get('user_prompt', '').strip()
            
            if file.filename == '':
                return jsonify({'error': 'No file selected'}), 400
            
            if not allowed_file(file.filename):
                return jsonify({'error': f'Unsupported file format. Supported formats: {", ".join(ALLOWED_EXTENSIONS)}'}), 400
            
            # Save uploaded file
            filename = secure_filename(file.filename)
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], f"{int(time.time())}_{filename}")
            file.save(filepath)
            
            # Get configuration from form data
            config = {}
            for key in request.form:
                if key != 'user_prompt' and key != 'video':
                    value = request.form.get(key)
                    if value == 'true':
                        config[key] = True
                    elif value == 'false':
                        config[key] = False
                    elif value.replace('.', '').replace('-', '').isdigit():
                        config[key] = float(value) if '.' in value else int(value)
                    else:
                        config[key] = value
        else:
            # JSON mode (legacy support)
            data = request.get_json()
            video_data = data.get('video_data')
            video_filename = data.get('video_filename', 'uploaded_video.mp4')
            user_prompt = data.get('message', '').strip()
            config = data.get('config', {})
            
            if not video_data:
                return jsonify({'error': 'Video data is required'}), 400
            
            # Decode and save video file
            try:
                if video_data.startswith('data:'):
                    video_data = video_data.split(',')[1]
                
                video_bytes = base64.b64decode(video_data)
                filename = secure_filename(video_filename)
                filepath = os.path.join(app.config['UPLOAD_FOLDER'], f"{int(time.time())}_{filename}")
                
                with open(filepath, 'wb') as f:
                    f.write(video_bytes)
                    
            except Exception as e:
                return jsonify({'error': f'Failed to decode video data: {str(e)}'}), 400
        
        if not user_prompt:
            return jsonify({'error': 'User prompt is required'}), 400
        
        # Extract configuration parameters
        azure_endpoint = config.get('azure_endpoint', '').strip()
        azure_api_key = config.get('azure_api_key', '').strip()
        llm_model = config.get('llm_model', 'gpt-4o-mini').strip()
        
        # Audio configuration with model names
        audio_endpoint = config.get('audio_endpoint', '').strip() or azure_endpoint
        audio_api_key = config.get('audio_api_key', '').strip() or azure_api_key
        audio_main_model = config.get('audio_main_model', 'gpt-4o-audio-preview').strip()
        audio_v2_model = config.get('audio_v2_model', 'whisper').strip()
        audio_v3_model = config.get('audio_v3_model', 'gpt-4o-mini-transcribe').strip()
        
        enable_audio_analysis = config.get('enable_audio_analysis', False)
        enable_v2_audio = config.get('enable_v2_audio', False)
        enable_v3_audio = config.get('enable_v3_audio', False)
        
        system_prompt = config.get('system_prompt', '').strip()
        audio_prompt = config.get('audio_prompt', '').strip()
        
        if not azure_endpoint or not azure_api_key:
            return jsonify({'error': 'Azure OpenAI configuration is required'}), 400
        
        print(f"Processing video: {filepath}")
        print(f"LLM Model: {llm_model}")
        print(f"Audio Models: Main={audio_main_model}, V2={audio_v2_model}, V3={audio_v3_model}")
        print(f"Audio Analysis: {enable_audio_analysis}, V2: {enable_v2_audio}, V3: {enable_v3_audio}")
        
        # Set environment variables for process_video to use
        os.environ['AZURE_OPENAI_ENDPOINT'] = azure_endpoint
        os.environ['AZURE_OPENAI_API_KEY'] = azure_api_key
        os.environ['AZURE_OPENAI_DEPLOYMENT_NAME'] = llm_model
        
        # Set audio environment variables if audio analysis is enabled
        if enable_audio_analysis:
            os.environ['AUDIO_ENDPOINT_URL'] = audio_endpoint
            os.environ['AUDIO_AZURE_OPENAI_API_KEY'] = audio_api_key
            os.environ['AUDIO_DEPLOYMENT_NAME'] = audio_main_model
            if enable_v2_audio:
                os.environ['AUDIO_DEPLOYMENT_NAME_V2'] = audio_v2_model
            if enable_v3_audio:
                os.environ['AUDIO_DEPLOYMENT_NAME_V3'] = audio_v3_model
        
        # Build extraction parameters
        extraction_params = {}
        
        # Only include parameters that are explicitly set
        if config.get('max_frames') is not None:
            extraction_params['max_frames'] = config.get('max_frames')
        if config.get('min_time_gap') is not None:
            extraction_params['min_time_gap'] = config.get('min_time_gap')
        if config.get('enable_image_enhancement'):
            extraction_params['enable_image_enhancement'] = True
        if config.get('min_frames_after_dedup') is not None:
            extraction_params['min_frames_after_dedup'] = config.get('min_frames_after_dedup')
        if config.get('frame_gap') is not None:
            extraction_params['frame_gap'] = config.get('frame_gap')
        if config.get('motion_weight') is not None:
            extraction_params['motion_weight'] = config.get('motion_weight')
        if config.get('scene_weight') is not None:
            extraction_params['scene_weight'] = config.get('scene_weight')
        if config.get('color_weight') is not None:
            extraction_params['color_weight'] = config.get('color_weight')
        if config.get('edge_weight') is not None:
            extraction_params['edge_weight'] = config.get('edge_weight')
        if config.get('content_frame_bar') is not None:
            extraction_params['content_frame_bar'] = config.get('content_frame_bar')
        if config.get('enable_deduplication') is not None:
            extraction_params['enable_deduplication'] = config.get('enable_deduplication')
        if config.get('similarity_threshold') is not None:
            extraction_params['similarity_threshold'] = config.get('similarity_threshold')
        if config.get('maximum_dimension') is not None:
            extraction_params['maximum_dimension'] = config.get('maximum_dimension')
        
        # Build audio config
        audio_config = {}
        if enable_audio_analysis:
            audio_config['enable_v2'] = enable_v2_audio
            audio_config['enable_v3'] = enable_v3_audio
            if audio_prompt:
                audio_config['user_prompt'] = audio_prompt
        
        print(f"Starting video processing using process_video function...")
        start_time = time.time()
        
        # Use process_video function directly
        result = process_video(
            video_input=filepath,
            system_prompt=system_prompt if system_prompt else None,
            user_prompt=user_prompt,
            extraction_params=extraction_params if extraction_params else None,
            audio_config=audio_config if audio_config else None,
            enable_audio_analysis=enable_audio_analysis,
            cleanup_temp=False  
        )
        
        processing_time = time.time() - start_time
        
        print(f"Video processing completed in {processing_time:.2f} seconds")
        
        if not result.get("success"):
            return jsonify({'error': f'Processing failed: {result.get("error")}'}), 400
        
        # Extract data from result
        analysis_content = result.get('analysis_result', {}).get('analysis', 'No analysis available')
        keyframes_data = result.get('extraction_result', {}).get('keyframes', [])
        audio_analysis_result = result.get('audio_analysis_result')
        
        # Create comprehensive response
        response_content = f"**Video Analysis Results:**\n\n{analysis_content}"
        
        # if audio_analysis_result and audio_analysis_result.get('success'):
            # audio_content = audio_analysis_result.get('analysis', 'No audio analysis available')
            # response_content += f"\n\n**Audio Analysis:**\n\n{audio_content}"

        # Processing information
        processing_info = {
            'processing_time': round(processing_time, 2),
            'keyframes_count': len(keyframes_data),
            'audio_enabled': enable_audio_analysis and audio_analysis_result and audio_analysis_result.get('success', False),
            'usage': {
                'vision_usage': result.get('pipeline_info', {}).get('usage', {}).get('vision_usage', 0),
                'audio_usage': result.get('pipeline_info', {}).get('usage', {}).get('audio_usage', 0) if audio_analysis_result and audio_analysis_result.get('success') else 0
            }
        }

        return jsonify({
            'success': True,
            'analysis': response_content,
            'keyframes': keyframes_data, 
            'processing_info': processing_info,
            'audio_analysis': audio_analysis_result.get('analysis') if audio_analysis_result and audio_analysis_result.get('success') else None,
            'model_used': llm_model,
            'audio_models_used': {
                'main': audio_main_model,
                'v2': audio_v2_model if enable_v2_audio else None,
                'v3': audio_v3_model if enable_v3_audio else None
            } if enable_audio_analysis else None,
            'video_info': result.get('video_info', {}),
            'pipeline_info': result.get('pipeline_info', {})
        })
        
    except Exception as e:
        print(f"Chat processing failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': f'Processing failed: {str(e)}'}), 500
    
    finally:
        # Clean up temporary files
        if filepath and os.path.exists(filepath):
            try:
                time.sleep(1)
                os.remove(filepath)
                print(f"Cleaned up temporary video file: {filepath}")
            except Exception as e:
                print(f"Failed to clean up video file: {e}")

@app.route('/keyframes/<filename>')
def serve_keyframe(filename):
    """Serve keyframe images"""
    return send_from_directory('keyframes_output', filename)

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'timestamp': int(time.time())})

# Start file cleanup timer
start_file_cleanup_timer()

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)