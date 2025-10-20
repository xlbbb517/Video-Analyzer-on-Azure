FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsm6 \
    libxext6 \
    libfontconfig1 \
    libxrender1 \
    libgl1-mesa-dri \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt fastapi uvicorn python-multipart

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p uploads keyframes_output audio_output

# Expose port
EXPOSE 5000

# Start command
CMD ["python", "api.py"]