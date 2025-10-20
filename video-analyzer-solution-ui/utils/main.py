"""
Main video analysis program
"""

import os
import tempfile
import logging
import argparse
from typing import Dict, Optional, Any
from datetime import datetime
import shutil
from urllib.parse import urlparse
from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv

from utils.frame_extractor import EnhancedKeyFrameExtractor
from utils.audio_extractor import AudioAnalyzer, extract_audio_from_video
from utils.analyzer import VideoAnalyzer

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def download_video_from_storage(blob_path: str) -> Optional[str]:
    """
    Download video file from Azure Storage

    Args:
        blob_path: Blob storage path

    Returns:
        Local file path, or None if failed
    """
    try:
        # Get Storage configuration
        storage_connection_string = os.getenv('AZURE_STORAGE_CONNECTION_STRING')
        storage_account_name = os.getenv('AZURE_STORAGE_ACCOUNT_NAME')
        storage_account_key = os.getenv('AZURE_STORAGE_ACCOUNT_KEY')
        storage_container_name = os.getenv('AZURE_STORAGE_CONTAINER_NAME', 'videos')
        
        if not any([storage_connection_string, 
                   (storage_account_name and storage_account_key)]):
            logger.error("Azure Storage configuration is missing, please check your .env file")
            return None

        # Initialize Azure Storage client
        if storage_connection_string:
            blob_service_client = BlobServiceClient.from_connection_string(
                storage_connection_string
            )
        else:
            account_url = f"https://{storage_account_name}.blob.core.windows.net"
            blob_service_client = BlobServiceClient(
                account_url=account_url,
                credential=storage_account_key
            )

        blob_client = blob_service_client.get_blob_client(
            container=storage_container_name,
            blob=blob_path
        )

        if not blob_client.exists():
            logger.error(f"Blob does not exist: {blob_path}")
            return None

        # Create temporary directory and file path
        temp_dir = tempfile.mkdtemp(prefix="video_download_")
        filename = os.path.basename(blob_path)
        local_path = os.path.join(temp_dir, filename)

        with open(local_path, "wb") as download_file:
            download_stream = blob_client.download_blob()
            download_file.write(download_stream.readall())

        logger.info(f"Video downloaded successfully: {local_path}")
        return local_path
        
    except Exception as e:
        logger.error(f"Failed to download video: {str(e)}")
        return None

def get_video_path(video_input: str) -> tuple[Optional[str], bool]:
    """
    Process video path, supporting local files and Storage blobs

    Args:
        video_input: Video input path (local path or blob path)

    Returns:
        (Local video path, is temporary file)
    """
    # Check if it's a local file
    if os.path.exists(video_input):
        return video_input, False

    # Check if it's a URL or blob path
    if video_input.startswith(('http://', 'https://', 'blob://')):
        # Here you can extend support for HTTP URL downloads
        logger.info(f"Videos from URLs are not supported yet, you can add the download logic.")
        return None, False

    # Process as Azure Storage blob path
    logger.info(f"Processing as Azure Storage blob: {video_input}")
    local_path = download_video_from_storage(video_input)
    return local_path, True

def process_video(video_input: str,
                 system_prompt: str = None,
                 user_prompt: str = None,
                 extraction_params: Dict[str, Any] = None,
                 audio_config: Dict[str, Any] = None, 
                 enable_audio_analysis: bool = False,
                 cleanup_temp: bool = True) -> Dict:
    """
    General video processing function

    Args:
        video_input: Video input (local path or blob path)
        system_prompt: System prompt
        user_prompt: User prompt
        extraction_params: Extraction parameters dictionary
        audio_config: Audio analysis configuration
        enable_audio_analysis: Whether to enable audio analysis
        cleanup_temp: Whether to clean up temporary files
        
    Returns:
        Processing result
    """
    start_time = datetime.now()
    local_video_path = None
    is_temp_file = False
    temp_audio_path = None 
    
    try:        
        # Initialize detailed usage tracking
        total_usage = {
            'vision_usage': {
                'completion_tokens': 0,
                'prompt_tokens': 0,
                'total_tokens': 0,
                'completion_tokens_details': {},
                'prompt_tokens_details': {}
            },
            'audio_usage': {
                'completion_tokens': 0,
                'prompt_tokens': 0,
                'total_tokens': 0,
                'completion_tokens_details': {},
                'prompt_tokens_details': {}
            }
        }

        local_video_path, is_temp_file = get_video_path(video_input)
        if not local_video_path:
            return {"error": "Failed to get local video path"}

        extractor = EnhancedKeyFrameExtractor()
        analyzer = VideoAnalyzer()
        
        logger.info("Start to extract keyframes...")
        
        extract_params = {'video_path': local_video_path}
        if extraction_params:
            extract_params.update(extraction_params)
        
        keyframes = extractor.extract_keyframes(**extract_params)
        
        if not keyframes:
            return {"error": "Failed to extract keyframes"}

        logger.info(f"Successfully extracted {len(keyframes)} keyframes")

        audio_analysis_result = None
        if enable_audio_analysis:
            try:

                default_audio_config = {
                    'enable_v2': False,
                    'enable_v3': False,
                    'user_prompt': "Please describe what happens in this audio. If there are conversations, provide transcriptions. Describe any sounds you hear, including background noises, music, sound effects, environmental sounds, etc. Please provide a comprehensive analysis in English.",
                    'audio_format': 'mp3'
                }
                
                if audio_config:
                    default_audio_config.update(audio_config)
                
                logger.info("Start to extract and analyze audio...")

                video_filename = os.path.splitext(os.path.basename(local_video_path))[0]
                temp_audio_path = os.path.join(tempfile.gettempdir(), f"{video_filename}_temp.mp3")
                
                extracted_audio_path = extract_audio_from_video(
                    video_path=local_video_path,
                    output_path=temp_audio_path,
                    audio_format=default_audio_config['audio_format']
                )
                
                if extracted_audio_path:
                    audio_analyzer = AudioAnalyzer()
                    audio_analysis_result = audio_analyzer.analyze_audio_file_multi_model(
                        audio_path=extracted_audio_path,
                        use_v2=default_audio_config.get('enable_v2', False),
                        use_v3=default_audio_config.get('enable_v3', False),
                        user_prompt=default_audio_config.get('user_prompt'),
                        audio_format=default_audio_config['audio_format']
                    )

                    if audio_analysis_result.get('results').get('main').get('usage'):
                        total_usage['audio_usage'] = audio_analysis_result['results']['main']['usage']

                    if audio_analysis_result.get('success'):
                        logger.info(f"Audio analysis completed successfully")
                    else:
                        logger.warning(f"Audio analysis failed: {audio_analysis_result.get('error', 'Unknown error')}")
                else:
                    logger.warning("Audio extraction failed")
                    audio_analysis_result = {'success': False, 'error': 'Audio extraction failed'}
                
            except Exception as e:
                logger.error(f"Audio analysis error: {str(e)}")
                audio_analysis_result = {'success': False, 'error': str(e)}
        else:
            logger.info("Audio analysis is disabled")

        images = [frame['base64_image'] for frame in keyframes]
        
        logger.info("Start to analyze content...")
        analysis_result = analyzer.analyze_frames(
            images=images,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            audio_analysis=audio_analysis_result 
        )

        if analysis_result.get('usage'):
            total_usage['vision_usage'] = analysis_result['usage']

        processing_time = (datetime.now() - start_time).total_seconds()

        mode = "storage_video" if is_temp_file else "local_video"
        
        result = {
            "success": True,
            "mode": mode,
            "video_info": {
                "original_input": video_input,
                "local_path": local_video_path,
                "is_temp_file": is_temp_file,
                "processing_time": processing_time
            },
            "extraction_result": {
                "keyframes_count": len(keyframes),
                "keyframes": keyframes,
                "extraction_params": extract_params
            },
            "audio_analysis_result": audio_analysis_result, 
            "analysis_result": analysis_result,
            "pipeline_info": {
                "start_time": start_time.isoformat(),
                "total_processing_time": processing_time,
                "audio_analysis_enabled": enable_audio_analysis,
                "usage": total_usage
            }
        }

        logger.info(f"Finished processing video: {processing_time:.2f}s")
        return result
        
    except Exception as e:
        logger.error(f"Failed to process video: {str(e)}")
        return {
            "error": f"Failed to process video: {str(e)}",
            "processing_time": (datetime.now() - start_time).total_seconds()
        }
    
    finally:
        if cleanup_temp:
            if is_temp_file and local_video_path and os.path.exists(local_video_path):
                try:
                    os.remove(local_video_path)
                    temp_dir = os.path.dirname(local_video_path)
                    if os.path.exists(temp_dir):
                        shutil.rmtree(temp_dir)
                    logger.info(f"Finished cleaning up temporary video files: {local_video_path}")
                except Exception as cleanup_error:
                    logger.warning(f"Failed to clean up temporary video files: {cleanup_error}")

            if temp_audio_path and os.path.exists(temp_audio_path):
                try:
                    os.remove(temp_audio_path)
                    logger.info(f"Finished cleaning up temporary audio files: {temp_audio_path}")
                except Exception as cleanup_error:
                    logger.warning(f"Failed to clean up temporary audio files: {cleanup_error}")

def create_argument_parser():
    """Create command line argument parser"""
    parser = argparse.ArgumentParser(description='Video Analysis Tool')

    # Basic parameters
    parser.add_argument('video_input', help='video input path (local file or Azure blob)')
    parser.add_argument('--system-prompt', default=None, help='system prompt')
    parser.add_argument('--user-prompt', default=None, help='user prompt')

    # Audio parameters
    parser.add_argument('--enable-audio-analysis', action='store_true', help='Enable audio analysis')
    parser.add_argument('--audio-enable-v2', action='store_true', help='Enable V2 audio model (whisper)')
    parser.add_argument('--audio-enable-v3', action='store_true', help='Enable V3 audio model (gpt-4o-mini-transcribe)')
    parser.add_argument('--audio-prompt', default=None, help='Audio analysis prompt')

    # Extraction parameters
    parser.add_argument('--max-frames', type=int, help='maximum number of keyframes (default: 12)')
    parser.add_argument('--min-time-gap', type=float, help='minimum time gap (seconds) (default: 0.8)')
    parser.add_argument('--enable-image-enhancement', action='store_true', help='enable image enhancement (default: False)')
    parser.add_argument('--min-frames-after-dedup', type=int, help='minimum frames to keep after deduplication (default: 3)')
    parser.add_argument('--frame-gap', type=int, help='frame analysis interval (default: 5)')
    parser.add_argument('--motion-weight', type=float, help='motion change weight (default: 3.0)')
    parser.add_argument('--scene-weight', type=float, help='scene change weight (default: 1.5)')
    parser.add_argument('--color-weight', type=float, help='color change weight (default: 0.5)')
    parser.add_argument('--edge-weight', type=float, help='edge change weight (default: 2.0)')
    parser.add_argument('--content-frame-bar', type=float, help='content frame selection ratio (default: 0.5)')
    parser.add_argument('--enable-deduplication', action='store_true', help='enable deduplication (default: True)')
    parser.add_argument('--disable-deduplication', action='store_true', help='disable deduplication')
    parser.add_argument('--similarity-threshold', type=float, help='similarity threshold (default: 0.95)')
    parser.add_argument('--maximum-dimension', type=int, help='maximum dimension limit (default: 480)')

    # Other options
    parser.add_argument('--no-cleanup', action='store_true', help='do not clean up temporary files')
    parser.add_argument('--verbose', '-v', action='store_true', help='verbose output')

    return parser

def args_to_audio_config(args) -> Dict[str, Any]:
    """Convert command line arguments to audio configuration dictionary"""
    audio_config = {}
    
    if hasattr(args, 'audio_enable_v2') and args.audio_enable_v2:
        audio_config['enable_v2'] = True
    if hasattr(args, 'audio_enable_v3') and args.audio_enable_v3:
        audio_config['enable_v3'] = True
    if hasattr(args, 'audio_prompt') and args.audio_prompt:
        audio_config['user_prompt'] = args.audio_prompt
    
    return audio_config

def args_to_extraction_params(args) -> Dict[str, Any]:
    """Convert command line arguments to extraction parameters dictionary, only including user-set parameters"""
    params = {}
    
    if args.max_frames is not None:
        params['max_frames'] = args.max_frames
    if args.min_time_gap is not None:
        params['min_time_gap'] = args.min_time_gap
    if args.enable_image_enhancement:
        params['enable_image_enhancement'] = True
    if args.min_frames_after_dedup is not None:
        params['min_frames_after_dedup'] = args.min_frames_after_dedup
    if args.frame_gap is not None:
        params['frame_gap'] = args.frame_gap
    if args.motion_weight is not None:
        params['motion_weight'] = args.motion_weight
    if args.scene_weight is not None:
        params['scene_weight'] = args.scene_weight
    if args.color_weight is not None:
        params['color_weight'] = args.color_weight
    if args.edge_weight is not None:
        params['edge_weight'] = args.edge_weight
    if args.content_frame_bar is not None:
        params['content_frame_bar'] = args.content_frame_bar
    if args.disable_deduplication:
        params['enable_deduplication'] = False
    elif args.enable_deduplication:
        params['enable_deduplication'] = True
    if args.similarity_threshold is not None:
        params['similarity_threshold'] = args.similarity_threshold
    if args.maximum_dimension is not None:
        params['maximum_dimension'] = args.maximum_dimension
    
    return params

def main():
    """Main function"""
    parser = create_argument_parser()
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    extraction_params = args_to_extraction_params(args)
    audio_config = args_to_audio_config(args)
    
    result = process_video(
        video_input=args.video_input,
        system_prompt=args.system_prompt,
        user_prompt=args.user_prompt,
        extraction_params=extraction_params,
        audio_config=audio_config, 
        enable_audio_analysis=args.enable_audio_analysis,
        cleanup_temp=not args.no_cleanup
    )
    
    if result.get("success"):
        print("Video processing completed successfully!")
        print(f"Extracted {result['extraction_result']['keyframes_count']} keyframes")
        print(f"Processing time: {result['pipeline_info']['total_processing_time']:.2f} seconds")
        print(f"Processing mode: {result['mode']}")

        if 'analysis' in result['analysis_result']:
            print(f"Analysis result: {result['analysis_result']['analysis']}")
    else:
        print(f"Processing failed: {result.get('error')}")
        return 1
    
    return 0

def main_cli():
    """Command line interface - only used for local testing"""
    parser = create_argument_parser()
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    extraction_params = args_to_extraction_params(args)
    audio_config = args_to_audio_config(args)
    
    result = process_video(
        video_input=args.video_input,
        system_prompt=args.system_prompt,
        user_prompt=args.user_prompt,
        extraction_params=extraction_params,
        audio_config=audio_config, 
        enable_audio_analysis=args.enable_audio_analysis,
        cleanup_temp=not args.no_cleanup
    )
    
    if result.get("success"):
        print("Video processing completed successfully!")
        print(f"Extracted {result['extraction_result']['keyframes_count']} keyframes")
        print(f"Processing time: {result['pipeline_info']['total_processing_time']:.2f} seconds")
        print(f"Processing mode: {result['mode']}")

        if 'analysis' in result['analysis_result']:
            print(f"Analysis result: {result['analysis_result']['analysis']}")
    else:
        print(f"Processing failed: {result.get('error')}")
        return 1
    
    return 0

if __name__ == "__main__":
    import sys
    
    # Only run CLI if called directly with arguments
    if len(sys.argv) > 1:
        sys.exit(main_cli())
    else:
        print("This is the main processing module. Use api.py to start the web service.")
        print("For CLI usage: python main.py <video_path> [options]")