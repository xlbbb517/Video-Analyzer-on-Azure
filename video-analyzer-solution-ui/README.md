# Video Analyzer on Azure

A comprehensive AI-powered video analysis solution on Azure. This application enables intelligent video content analysis through frame extraction, audio transcription, and multimodal AI processing.

## Features

- **Video Upload & Processing**: Support for multiple video formats (MP4, AVI, MOV, MKV, FLV, WMV, WebM, M4V)
- **Intelligent Frame Extraction**: Advanced keyframe extraction with adjustable selection strategy
- **Audio Analysis**: Optional audio transcription and analysis using Azure OpenAI audio models
- **Multimodal AI Analysis**: Combined vision and audio analysis for comprehensive video understanding
- **Configuration Management**: Export/import settings for easy deployment across environments

## Project Structure

```
video-analyzer-solution/
├── app.py                      # Main Flask application
├── requirements.txt            # Python dependencies
├── Dockerfile                  # Container configuration
├── deploy.ps1                  # Azure deployment script
├── README.md                   # Project documentation
│
├── templates/
│   └── index.html             # Main web interface
│
├── static/
│   ├── css/
│   │   └── styles.css         # Application styling
│   ├── js/
│   │   └── app.js            # Frontend JavaScript logic
│   └── images/
│       └── Video.svg         # Application assets
│
└── utils/
    ├── main.py               # Core processing logic
    ├── analyzer.py           # Video analysis engine
    ├── frame_extractor.py    # Frame extraction utilities
    └── audio_extractor.py    # Audio processing utilities
```

## Installation

### Prerequisites

- Python 3.9 or higher
- Azure OpenAI service access
- FFmpeg (for video processing)

### Local Setup

1. **Clone the repository**
```bash
git clone <repository-url>
cd video-analyzer-solution
```

2. **Install dependencies**
```bash
pip install -r requirements.txt
```

3. **Run the application**

```bash
python app.py
```

The application will be available at `http://localhost:5000`

## Azure Container Apps Deployment

### Prerequisites

- Azure CLI installed and configured
- Azure subscription with Container Apps enabled

### Deployment Steps

1. **Configure deployment variables**

Edit `deploy.ps1` and update the following variables:
```powershell
$RESOURCE_GROUP = "your-resource-group"
$LOCATION = "eastus"  # or your preferred region
$CONTAINER_APP_ENV = "video-analyzer-env"
$CONTAINER_APP_NAME = "video-analyzer-app"
```

2. **Run deployment script**
```powershell
# Set execution policy (if needed)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Run deployment
.\deploy.ps1
```

The script will:
- Create Azure Container Registry
- Build and push the Docker image
- Create Container Apps environment
- Deploy the application
- Provide the public URL

## Usage

### Getting Started

1. **Configure Azure OpenAI**: Enter your Azure OpenAI endpoint and API key in the settings panel
2. **Upload Video**: Click the paperclip icon to upload a video file (max 500MB)
3. **Ask Questions**: Type questions about your video content
4. **Review Results**: View AI analysis with extracted keyframes and processing statistics

### Advanced Configuration

#### Frame Extraction Settings
- **Max Frames**: Maximum number of keyframes to extract (1-50)
- **Min Time Gap**: Minimum time between extracted frames (seconds)
- **Frame Gap**: Skip frames for processing efficiency
- **Deduplication**: Remove similar frames automatically
- **Image Enhancement**: Apply quality improvements to extracted frames

#### Audio Analysis Options
- **Enable Audio Analysis**: Process audio track alongside video
- **V2 Audio**: Use Whisper model for transcription
- **V3 Audio**: Use GPT-4o-mini for transcription
- **Custom Audio Prompt**: Specify analysis requirements

#### Advanced Settings
- **Motion Weight**: Prioritize frames with motion (0-10)
- **Scene Weight**: Prioritize scene changes (0-10)
- **Color Weight**: Consider color distribution (0-10)
- **Edge Weight**: Consider edge density (0-10)
- **Similarity Threshold**: Deduplication sensitivity (0-1)
- **Maximum Dimension**: Resize frames for processing (pixels)

### Configuration Management

- **Export Settings**: Download current configuration as JSON
- **Import Settings**: Upload configuration file to restore settings
- **Auto-save**: Settings are automatically saved to browser storage

## API Reference

### Main Endpoint

```http
POST /chat
Content-Type: multipart/form-data
```

**Parameters:**
- `video`: Video file (required)
- `user_prompt`: Analysis question (required)
- `azure_endpoint`: Azure OpenAI endpoint (required)
- `azure_api_key`: Azure OpenAI API key (required)
- Additional configuration parameters as form data

**Response:**
```json
{
  "analysis": "AI analysis text",
  "keyframes": [...],
  "processing_info": {
    "processing_time": 15.2,
    "keyframes_count": 8,
    "audio_enabled": true,
    "usage": {
      "vision_usage": {...},
      "audio_usage": {...}
    }
  }
}
```

## Copyright Notice

```
© 2025 GCR DN Tech Team, Microsoft Corporation
All rights reserved.
```

---

**Built with ❤️ by the GCR DN Tech Team at Microsoft**



