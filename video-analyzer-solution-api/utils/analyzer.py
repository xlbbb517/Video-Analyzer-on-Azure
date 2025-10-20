"""
VideoAnalyzer
Use Azure OpenAI to analyze keyframes
"""

import os
import json
import logging
from typing import List, Dict, Optional
import requests
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class VideoAnalyzer:
    """Video content analyzer - VideoAnalyzer"""
    
    def __init__(self, endpoint = None, api_key = None, api_version = None, deployment_name = None):
        """Initialize the analyzer and load configuration from environment variables"""
        self.endpoint = endpoint or os.getenv('AZURE_OPENAI_ENDPOINT')
        self.api_key = api_key or os.getenv('AZURE_OPENAI_API_KEY')
        self.api_version = api_version or os.getenv('AZURE_OPENAI_API_VERSION', '2024-02-15-preview')
        self.deployment_name = deployment_name or os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME', 'gpt-4o')
        
        if not self.endpoint or not self.api_key:
            raise ValueError("No Azure OpenAI configuration found, please check your .env file")

        self.url = f"{self.endpoint.rstrip('/')}/openai/deployments/{self.deployment_name}/chat/completions?api-version={self.api_version}"

        self.headers = {
            "Content-Type": "application/json",
            "api-key": self.api_key
        }

        logger.info(f"VideoAnalyzer Initialized: {self.endpoint}")

    def analyze_frames(self,
                  images: List[str],
                  system_prompt: str = None,
                  user_prompt: str = None,
                  audio_analysis: Dict = None) -> Dict:  
        """
        Analyze video frames and audio content

        Args:
            images: base64 encoded image list
            system_prompt: system prompt
            user_prompt: user prompt
            audio_analysis: audio analysis result dictionary

        Returns:
            Analysis result dictionary
        """
        
        if not images:
            return {"error": "No images provided for analysis"}

        # Default prompts
        if not system_prompt:
            system_prompt = "You are a professional video content analyst who can accurately understand and describe video content."
        if not user_prompt:
            user_prompt = "Please analyze these video keyframes and describe the main content, scenes, characters, and important events."

        # If audio analysis is successful, enhance user prompt
        if audio_analysis and audio_analysis.get('success'):
            audio_content = audio_analysis.get('analysis', '')
            enhanced_user_prompt = f"""{user_prompt}

    [Audio Analysis Results]
    {audio_content}

    Please combine the visual information from the keyframes with the audio analysis above to provide a comprehensive video content analysis. Consider how the audio and visual elements work together to convey the overall message and content of the video."""
            
            logger.info("Enhanced prompt with audio analysis results")
        elif audio_analysis and not audio_analysis.get('success'):
            enhanced_user_prompt = f"""{user_prompt}

    Note: Audio analysis was attempted but failed ({audio_analysis.get('error', 'Unknown error')}). Please analyze based on the visual keyframes only."""
            
            logger.warning(f"Audio analysis failed: {audio_analysis.get('error', 'Unknown error')}")
        else:
            enhanced_user_prompt = user_prompt
            logger.info("No audio analysis provided, analyzing visual content only")

        try:
            messages = [
                {
                    "role": "system",
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": enhanced_user_prompt 
                        }
                    ]
                }
            ]

            for i, image in enumerate(images):
                if image.startswith('data:image/'):
                    image_url = image
                else:
                    image_url = f"data:image/jpeg;base64,{image}"
                
                messages[1]["content"].append({
                    "type": "image_url",
                    "image_url": {
                        "url": image_url,
                        "detail": "low"
                    }
                })

            payload = {
                "messages": messages
            }

            response = requests.post(
                self.url,
                headers=self.headers,
                json=payload,
                timeout=120
            )

            if response.status_code == 200:
                result = response.json()

                if 'choices' in result and len(result['choices']) > 0:
                    analysis_text = result['choices'][0]['message']['content']
                    usage = result.get('usage', {})
                    detailed_usage = {
                        'completion_tokens': usage.get('completion_tokens', 0),
                        'prompt_tokens': usage.get('prompt_tokens', 0),
                        'total_tokens': usage.get('total_tokens', 0),
                        'completion_tokens_details': usage.get('completion_tokens_details', {}),
                        'prompt_tokens_details': usage.get('prompt_tokens_details', {})
                    }
                    
                    return {
                        "success": True,
                        "analysis": analysis_text,
                        "usage": detailed_usage,
                        "model": result.get('model', self.deployment_name),
                        "frames_count": len(images),
                        "audio_analysis_included": bool(audio_analysis and audio_analysis.get('success')),
                        "audio_analysis_status": audio_analysis.get('success', 'not_provided') if audio_analysis else 'not_provided'
                    }
                else:
                    return {"error": "API Response Format Error", "response": result}

            else:
                error_msg = f"API call failed, status code: {response.status_code}"
                try:
                    error_detail = response.json()
                    error_msg += f", error details: {error_detail}"
                except:
                    error_msg += f", response content: {response.text}"

                logger.error(error_msg)
                return {"error": error_msg}
                
        except requests.exceptions.Timeout:
            return {"error": "Request timed out, please try again later"}
        except requests.exceptions.RequestException as e:
            return {"error": f"Network request exception: {str(e)}"}
        except Exception as e:
            return {"error": f"An error occurred during analysis: {str(e)}"}