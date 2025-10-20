"""
AudioAnalyzer
Audio content extraction and analysis
"""
import glob
import os
import base64
import subprocess
import time
import logging
from typing import Dict, Any, List, Optional
from openai import AzureOpenAI

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AudioAnalyzer:
    """Audio content analyzer - AudioAnalyzer"""
    
    def __init__(self, endpoint=None, api_key=None, deployment_name=None, deployment_name_v2=None, deployment_name_v3=None):
        # If parameters are provided, use them; otherwise, use global configuration
        self.endpoint = endpoint or os.getenv("AUDIO_ENDPOINT_URL")
        self.deployment = deployment_name or os.getenv("AUDIO_DEPLOYMENT_NAME")
        self.deployment_v2 = deployment_name_v2 or os.getenv("AUDIO_DEPLOYMENT_NAME_V2")
        self.deployment_v3 = deployment_name_v3 or os.getenv("AUDIO_DEPLOYMENT_NAME_V3")
        self.subscription_key = api_key or os.getenv("AUDIO_AZURE_OPENAI_API_KEY")
        
        # Initialize Azure OpenAI client
        self.client = AzureOpenAI(
            azure_endpoint=self.endpoint,
            api_key=self.subscription_key,
            api_version="2025-01-01-preview",
        )
    
    def audio_file_to_base64(self, audio_path: str) -> Optional[str]:
        """Convert audio file to base64 encoding"""
        try:
            with open(audio_path, 'rb') as audio_file:
                audio_data = audio_file.read()
                encoded_audio = base64.b64encode(audio_data).decode('ascii')
                logger.info(f"Audio encoding successful, file size: {len(audio_data)} bytes")
                return encoded_audio
        except Exception as e:
            logger.error(f"Audio encoding failed: {str(e)}")
            return None
    
    def _combine_analysis_results(self, results: Dict[str, Dict]) -> str:
        """Combine analysis results from multiple models"""
        combined = []
        
        for model_key, result in results.items():
            if result.get('success'):
                model_name = result.get('model', model_key)
                analysis = result.get('analysis', '')
                combined.append(f"=== {model_name} Analysis Result ===\n{analysis}")

        return "\n\n".join(combined)

    def analyze_audio_multi_model(self, 
                                audio_data: str, 
                                use_v2: bool = False,
                                use_v3: bool = False,
                                system_prompt: str = None,
                                user_prompt: str = None,
                                audio_format: str = "wav",
                                temperature: float = 0.7) -> Dict[str, Any]:
        """
        Use multiple models to analyze audio content
        """
        results = {}
        total_time = 0

        # Main model analysis - Use original chat completions method
        main_result = self._analyze_with_chat_api(
            audio_data, self.deployment, system_prompt, user_prompt, audio_format, temperature
        )
        results['main'] = main_result
        if main_result.get('success'):
            total_time += main_result.get('analysis_time', 0)

        # V2 model analysis
        if use_v2 and self.deployment_v2:
            v2_result = self._analyze_with_audio_api(
                audio_data, self.deployment_v2, user_prompt, audio_format, temperature
            )
            results['v2'] = v2_result
            if v2_result.get('success'):
                total_time += v2_result.get('analysis_time', 0)

        # V3 model analysis
        if use_v3 and self.deployment_v3:
            v3_result = self._analyze_with_audio_api(
                audio_data, self.deployment_v3, user_prompt, audio_format, temperature
            )
            results['v3'] = v3_result
            if v3_result.get('success'):
                total_time += v3_result.get('analysis_time', 0)

        # Combine results
        combined_analysis = self._combine_analysis_results(results)
        
        return {
            'success': any(result.get('success', False) for result in results.values()),
            'analysis': combined_analysis,
            'analysis_time': round(total_time, 2),
            'results': results,
            'models_used': [model_key for model_key, result in results.items() if result.get('success')]
        }

    def analyze_audio_file_multi_model(self, 
                                    audio_path: str,
                                    use_v2: bool = False,
                                    use_v3: bool = False,
                                    system_prompt: str = None,
                                    user_prompt: str = None,
                                    audio_format: str = "wav",
                                    temperature: float = 0.7) -> Dict[str, Any]:
        """
        Analyze audio file using multiple models
        Args:
            audio_path: audio file path (pass in file path)
            use_v2: Whether to use V2 model (whisper)
            use_v3: Whether to use V3 model (gpt-4o-mini-transcribe)
            Other parameters are the same as above
        Returns:
            A dictionary containing the analysis results of all models
        """
        try:
            # Convert audio file to base64
            audio_data = self.audio_file_to_base64(audio_path)
            if not audio_data:
                return {
                    'success': False,
                    'error': 'Audio file encoding failed'
                }

            # Use multi-model analysis
            return self.analyze_audio_multi_model(
                audio_data, use_v2, use_v3, system_prompt, user_prompt, audio_format, temperature
            )
            
        except Exception as e:
            logger.error(f"Audio file analysis failed: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def _analyze_with_audio_api(self, 
                           audio_data: str, 
                           deployment_name: str,
                           user_prompt: str = None,
                           audio_format: str = "wav",
                           temperature: float = 0.7) -> Dict[str, Any]:
        """
        Use audio API for transcription
        """
        try:
            logger.info(f"Start using {deployment_name} for audio transcription...")
            start_time = time.time()

            # Convert base64 data to file object
            import io
            import base64

            # Extract actual audio data from base64
            if audio_data.startswith('data:audio/'):
                audio_data = audio_data.split(',')[1]

            # Decode base64
            audio_bytes = base64.b64decode(audio_data)
            audio_file = io.BytesIO(audio_bytes)
            audio_file.name = f"audio.{audio_format}"

            # Use /audio API for transcription
            result = self.client.audio.transcriptions.create(
                file=audio_file,
                model=deployment_name,
                prompt=user_prompt or "Transcribe this audio accurately.",
                response_format="text",
                temperature=temperature
            )
            
            analysis_time = time.time() - start_time
            transcription = result if isinstance(result, str) else result.text

            logger.info(f"{deployment_name} finished transcription, used: {analysis_time:.2f}s")

            return {
                'success': True,
                'analysis': f"Transcription result:\n{transcription}",
                'transcription': transcription,
                'analysis_time': round(analysis_time, 2),
                'model': deployment_name
            }
            
        except Exception as e:
            logger.error(f"Model {deployment_name} transcription failed: {str(e)}")
            return {
                'success': False,
                'error': str(e),
                'model': deployment_name
            }

    def _analyze_with_chat_api(self, 
                            audio_data: str, 
                            deployment_name: str,
                            system_prompt: str = None,
                            user_prompt: str = None,
                            audio_format: str = "wav",
                            temperature: float = 0.7) -> Dict[str, Any]:
        """
        Use chat completions API for audio analysis (main model)
        """
        try:
            # Default prompts
            if not system_prompt:
                # system_prompt = "You are an audio analysis expert. Analyze the audio content and provide detailed insights."
                system_prompt = ""
            
            if not user_prompt:
                user_prompt = "Transcribe the audio and analyze the emotions conveyed in it."

            messages = [
                {
                    "role": "system",
                    "content": [
                        {
                            "type": "text",
                            "text": system_prompt
                        }
                    ]
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": user_prompt
                        },
                        {
                            "type": "input_audio",
                            "input_audio": {
                                "data": audio_data,
                                "format": audio_format
                            }
                        }
                    ]
                }
            ]

            logger.info(f"Start using {deployment_name} for audio analysis...")
            start_time = time.time()

            # Call API
            completion = self.client.chat.completions.create(
                model=deployment_name,
                messages=messages,
                max_tokens=2000,
                temperature=temperature,
                top_p=0.95,
                frequency_penalty=0,
                presence_penalty=0,
                stop=None,
                stream=False
            )
            
            analysis_time = time.time() - start_time
            analysis_result = completion.choices[0].message.content.strip()

            # Collect all usage information
            total_usage = {
                'completion_tokens': 0,
                'prompt_tokens': 0,
                'total_tokens': 0,
                'completion_tokens_details': {},
                'prompt_tokens_details': {}
            }
            
            if completion.usage:
                usage = completion.usage
                total_usage['completion_tokens'] = usage.completion_tokens or 0
                total_usage['prompt_tokens'] = usage.prompt_tokens or 0
                total_usage['total_tokens'] = usage.total_tokens or 0
                
                if hasattr(usage, 'completion_tokens_details') and usage.completion_tokens_details:
                    total_usage['completion_tokens_details'] = usage.completion_tokens_details.__dict__
                if hasattr(usage, 'prompt_tokens_details') and usage.prompt_tokens_details:
                    total_usage['prompt_tokens_details'] = usage.prompt_tokens_details.__dict__

            logger.info(f"Main model {deployment_name} analysis completed, time taken: {analysis_time:.2f}s")
            return {
                'success': True,
                'analysis': analysis_result,
                'analysis_time': round(analysis_time, 2),
                'usage': total_usage,
                'model': deployment_name,
                'prompts': {
                    'system_prompt': system_prompt,
                    'user_prompt': user_prompt
                }
            }
            
        except Exception as e:
            logger.error(f"Main model {deployment_name} audio analysis failed: {str(e)}")
            return {
                'success': False,
                'error': str(e),
                'model': deployment_name
            }

def extract_audio_from_video(video_path: str, output_path: str = None, audio_format: str = "mp3", ffmpeg_path: str = "ffmpeg") -> Optional[str]:
    """
    Extract audio from video file
    Args:
        video_path: Path to the video file
        output_path: Path to the output audio file, if None it will be auto-generated
        audio_format: Audio format (mp3, wav, m4a, etc.)
        ffmpeg_path: Path to FFmpeg
    Returns:
        Path to the extracted audio file, None on failure
    """
    try:
        # If no output path is specified, auto-generate
        if output_path is None:
            video_name = os.path.splitext(os.path.basename(video_path))[0]
            output_dir = os.path.dirname(video_path)
            output_path = os.path.join(output_dir, f"{video_name}.wav")

        # Simple FFmpeg command to extract audio as WAV
        cmd = [
            'ffmpeg',
            '-y',  # Overwrite output file
            '-i', video_path,
            '-vn',  # No video
            output_path  # FFmpeg will use default settings for WAV
        ]

        logger.info(f"Extracting audio: {video_path} -> {output_path}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0:
            logger.info(f"Audio extraction succeeded: {output_path}")
            return output_path
        else:
            logger.error(f"Audio extraction failed: {result.stderr}")
            return None
            
    except Exception as e:
        logger.error(f"Audio extraction error: {str(e)}")
        return None