class VideoAnalyzerChat {
    constructor() {
        this.currentVideo = null;
        this.isProcessing = false;
        this.settingsVisible = true;
        this.isResizing = false;
        this.startX = 0;
        this.startWidth = 0;
        this.minPanelWidth = 300;
        this.maxPanelWidth = 600;
        this.currentKeyframes = [];
        this.currentKeyframeIndex = 0;
        this.fullscreenViewer = null;
        
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.setupResizer();
        this.updateSendButtonState();
        this.autoResizeTextarea();
        this.loadSettings();
        this.createFullscreenViewer();
        this.setupKeyboardNavigation();
    }
    
    createFullscreenViewer() {
        this.fullscreenViewer = document.createElement('div');
        this.fullscreenViewer.className = 'keyframe-fullscreen';
        this.fullscreenViewer.innerHTML = `
            <div class="keyframe-fullscreen-content">
                <img class="keyframe-fullscreen-image" src="" alt="Keyframe">
                <div class="keyframe-fullscreen-info">
                    <div class="frame-number"></div>
                    <div class="frame-time"></div>
                </div>
                <div class="keyframe-fullscreen-controls keyframe-prev" onclick="videoAnalyzerChat.prevKeyframe()">‹</div>
                <div class="keyframe-fullscreen-controls keyframe-next" onclick="videoAnalyzerChat.nextKeyframe()">›</div>
                <div class="keyframe-close" onclick="videoAnalyzerChat.closeFullscreen()">×</div>
                <div class="keyframe-counter">
                    <span class="current-frame">1</span> / <span class="total-frames">1</span>
                </div>
            </div>
        `;
        document.body.appendChild(this.fullscreenViewer);
        
        // Close on background click
        this.fullscreenViewer.addEventListener('click', (e) => {
            if (e.target === this.fullscreenViewer) {
                this.closeFullscreen();
            }
        });
    }
    
    setupKeyboardNavigation() {
        document.addEventListener('keydown', (e) => {
            if (this.fullscreenViewer && this.fullscreenViewer.classList.contains('active')) {
                switch(e.key) {
                    case 'Escape':
                        e.preventDefault();
                        this.closeFullscreen();
                        break;
                    case 'ArrowLeft':
                        e.preventDefault();
                        this.prevKeyframe();
                        break;
                    case 'ArrowRight':
                        e.preventDefault();
                        this.nextKeyframe();
                        break;
                    case ' ':
                        e.preventDefault();
                        // Space bar to toggle between prev/next
                        if (e.shiftKey) {
                            this.prevKeyframe();
                        } else {
                            this.nextKeyframe();
                        }
                        break;
                }
            }
        });
    }
    
    openKeyframeFullscreen(keyframes, index) {
        this.currentKeyframes = keyframes;
        this.currentKeyframeIndex = index;
        this.updateFullscreenKeyframe();
        this.fullscreenViewer.classList.add('active');
        document.body.style.overflow = 'hidden';
    }
    
    closeFullscreen() {
        if (this.fullscreenViewer) {
            this.fullscreenViewer.classList.remove('active');
            document.body.style.overflow = '';
        }
    }
    
    prevKeyframe() {
        if (this.currentKeyframes.length > 0) {
            this.currentKeyframeIndex = (this.currentKeyframeIndex - 1 + this.currentKeyframes.length) % this.currentKeyframes.length;
            this.updateFullscreenKeyframe();
        }
    }
    
    nextKeyframe() {
        if (this.currentKeyframes.length > 0) {
            this.currentKeyframeIndex = (this.currentKeyframeIndex + 1) % this.currentKeyframes.length;
            this.updateFullscreenKeyframe();
        }
    }
    
    updateFullscreenKeyframe() {
        if (!this.fullscreenViewer || this.currentKeyframes.length === 0) return;
        
        const frame = this.currentKeyframes[this.currentKeyframeIndex];
        const img = this.fullscreenViewer.querySelector('.keyframe-fullscreen-image');
        const frameNumber = this.fullscreenViewer.querySelector('.frame-number');
        const frameTime = this.fullscreenViewer.querySelector('.frame-time');
        const currentFrame = this.fullscreenViewer.querySelector('.current-frame');
        const totalFrames = this.fullscreenViewer.querySelector('.total-frames');
        
        // Handle different frame data structures
        const imageSrc = frame.base64_image || frame.image || frame.src;
        const frameNum = frame.frame_number || (this.currentKeyframeIndex + 1);
        const timestamp = frame.timestamp || 0;
        
        img.src = imageSrc;
        frameNumber.textContent = `Frame ${frameNum}`;
        frameTime.textContent = `Time: ${this.formatTimestamp(timestamp)}`;
        currentFrame.textContent = this.currentKeyframeIndex + 1;
        totalFrames.textContent = this.currentKeyframes.length;
        
        // Show/hide navigation controls
        const prevBtn = this.fullscreenViewer.querySelector('.keyframe-prev');
        const nextBtn = this.fullscreenViewer.querySelector('.keyframe-next');
        
        if (this.currentKeyframes.length <= 1) {
            prevBtn.style.display = 'none';
            nextBtn.style.display = 'none';
        } else {
            prevBtn.style.display = 'flex';
            nextBtn.style.display = 'flex';
        }
    }
    
    setupEventListeners() {
        // Video input handling
        const videoInput = document.getElementById('videoInput');
        videoInput.addEventListener('change', (e) => {
            this.handleVideoUpload(e.target.files[0]);
            // Reset input value to allow re-uploading the same file
            e.target.value = '';
        });
        
        // Also handle click event to reset value
        videoInput.addEventListener('click', (e) => {
            e.target.value = '';
        });
        
        // Audio analysis toggle
        document.getElementById('enableAudioAnalysis').addEventListener('change', (e) => {
            document.getElementById('audioConfig').style.display = e.target.checked ? 'block' : 'none';
        });
        
        // Message input handling
        const messageInput = document.getElementById('messageInput');
        messageInput.addEventListener('input', () => {
            this.updateSendButtonState();
            this.autoResizeTextarea();
        });
        
        messageInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });
        
        // Configuration validation
        ['azureEndpoint', 'azureApiKey'].forEach(id => {
            document.getElementById(id).addEventListener('input', () => {
                this.updateSendButtonState();
                this.saveSettings();
            });
        });
        
        // Save settings on input change
        const settingsInputs = [
            'azureEndpoint', 'azureApiKey', 'llmModel', 'audioEndpoint', 'audioApiKey', 
            'audioMainModel', 'audioV2Model', 'audioV3Model', 'systemPrompt', 'audioPrompt'
        ];
        
        settingsInputs.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.addEventListener('input', () => this.saveSettings());
            }
        });
    }
    
    setupResizer() {
        const resizer = document.getElementById('settingsResizer');
        const settingsPanel = document.getElementById('settingsPanel');
        
        if (!resizer || !settingsPanel) return;
        
        resizer.addEventListener('mousedown', (e) => {
            this.isResizing = true;
            this.startX = e.clientX;
            this.startWidth = parseInt(window.getComputedStyle(settingsPanel).width, 10);
            
            document.addEventListener('mousemove', this.handleResize.bind(this));
            document.addEventListener('mouseup', this.stopResize.bind(this));
            
            e.preventDefault();
        });
    }
    
    handleResize(e) {
        if (!this.isResizing) return;
        
        const settingsPanel = document.getElementById('settingsPanel');
        const deltaX = e.clientX - this.startX;
        const newWidth = this.startWidth + deltaX;
        
        if (newWidth >= this.minPanelWidth && newWidth <= this.maxPanelWidth) {
            settingsPanel.style.width = newWidth + 'px';
            document.documentElement.style.setProperty('--settings-panel-width', newWidth + 'px');
        }
    }
    
    stopResize() {
        this.isResizing = false;
        document.removeEventListener('mousemove', this.handleResize);
        document.removeEventListener('mouseup', this.stopResize);
        this.saveSettings();
    }
    
    autoResizeTextarea() {
        const textarea = document.getElementById('messageInput');
        if (textarea) {
            textarea.style.height = 'auto';
            textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
        }
    }
    
    updateSendButtonState() {
        const messageInput = document.getElementById('messageInput');
        const sendButton = document.getElementById('sendButton');
        const azureEndpoint = document.getElementById('azureEndpoint').value.trim();
        const azureApiKey = document.getElementById('azureApiKey').value.trim();
        
        const hasVideo = this.currentVideo !== null;
        const hasMessage = messageInput.value.trim().length > 0;
        const hasConfig = azureEndpoint.length > 0 && azureApiKey.length > 0;
        
        const canSend = hasVideo && hasMessage && hasConfig && !this.isProcessing;
        
        sendButton.disabled = !canSend;
        messageInput.disabled = !hasConfig;
        
        if (!hasConfig) {
            messageInput.placeholder = "Configure Azure OpenAI settings first...";
        } else if (!hasVideo) {
            messageInput.placeholder = "Upload a video first...";
        } else {
            messageInput.placeholder = "Ask a question about your video...";
        }
    }
    
    async handleVideoUpload(file) {
        if (!file) return;
        
        // Validate file type
        const allowedTypes = ['mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv', 'webm', 'm4v'];
        const fileExtension = file.name.split('.').pop().toLowerCase();
        
        if (!allowedTypes.includes(fileExtension)) {
            alert(`Unsupported file format. Supported formats: ${allowedTypes.join(', ')}`);
            return;
        }
        
        // Validate file size (500MB limit)
        const maxSize = 500 * 1024 * 1024;
        if (file.size > maxSize) {
            alert('File size exceeds 500MB limit. Please select a smaller file.');
            return;
        }
        
        try {
            this.currentVideo = file;
            
            // Add video message to chat
            this.addVideoMessage(file);
            this.updateSendButtonState();
            
        } catch (error) {
            console.error('Failed to process video:', error);
            alert('Failed to process video file.');
        }
    }
    
    addVideoMessage(file) {
        const messagesContainer = document.getElementById('chatMessages');
        
        // Hide welcome message if it exists
        const welcomeMessage = messagesContainer.querySelector('.welcome-message');
        if (welcomeMessage) {
            welcomeMessage.style.display = 'none';
        }
        
        const messageElement = document.createElement('div');
        messageElement.className = 'message user video-message';
        
        const url = URL.createObjectURL(file);
        
        messageElement.innerHTML = `
            <div class="message-avatar">U</div>
            <div class="message-content">
                <div class="video-preview-container">
                    <video class="video-preview" controls preload="metadata">
                        <source src="${url}" type="${file.type}">
                        Your browser does not support the video tag.
                    </video>
                    <div class="video-info">
                        <strong>${file.name}</strong>
                        <span>${(file.size / (1024 * 1024)).toFixed(2)} MB</span>
                        <button class="remove-video-btn" onclick="removeVideo()">
                            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
                                <path d="M12 4L4 12"/>
                                <path d="M4 4l8 8"/>
                            </svg>
                        </button>
                    </div>
                </div>
            </div>
        `;
        
        messagesContainer.appendChild(messageElement);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
    
    removeVideo() {
        this.currentVideo = null;
        
        // Reset UI
        document.getElementById('videoInput').value = '';
        
        // Remove video message from chat
        const videoMessage = document.querySelector('.video-message');
        if (videoMessage) {
            // Revoke object URL before removing
            const video = videoMessage.querySelector('video source');
            if (video && video.src) {
                URL.revokeObjectURL(video.src);
            }
            videoMessage.remove();
        }
        
        this.updateSendButtonState();
        
        // Show welcome message if no other messages
        const messagesContainer = document.getElementById('chatMessages');
        const messages = messagesContainer.querySelectorAll('.message');
        if (messages.length === 0) {
            this.showWelcomeMessage();
        }
    }
    
    showWelcomeMessage() {
        const messagesContainer = document.getElementById('chatMessages');
        messagesContainer.innerHTML = `
            <div class="welcome-message">
                <div class="welcome-icon">
                    <img src="/static/images/Video.svg" alt="Welcome" width="200" height="60">
                </div>
                <h3>Welcome to Video Analyzer On Azure</h3>
                <p>Upload a video and ask questions about its content. Configure your Azure OpenAI settings in the left panel to get started.</p>
            </div>
        `;
    }
    
    gatherConfiguration() {
        return {
            // Azure OpenAI Configuration
            azure_endpoint: document.getElementById('azureEndpoint').value.trim(),
            azure_api_key: document.getElementById('azureApiKey').value.trim(),
            llm_model: document.getElementById('llmModel').value.trim() || 'gpt-4o-mini',
            
            // Audio Configuration
            audio_endpoint: document.getElementById('audioEndpoint').value.trim(),
            audio_api_key: document.getElementById('audioApiKey').value.trim(),
            audio_main_model: document.getElementById('audioMainModel').value.trim() || 'gpt-4o-audio-preview',
            audio_v2_model: document.getElementById('audioV2Model').value.trim() || 'whisper',
            audio_v3_model: document.getElementById('audioV3Model').value.trim() || 'gpt-4o-mini-transcribe',
            enable_audio_analysis: document.getElementById('enableAudioAnalysis').checked,
            enable_v2_audio: document.getElementById('enableV2Audio').checked,
            enable_v3_audio: document.getElementById('enableV3Audio').checked,
            audio_prompt: document.getElementById('audioPrompt').value.trim(),
            
            // System Prompt
            system_prompt: document.getElementById('systemPrompt').value.trim(),
            
            // Frame Extraction Settings
            max_frames: parseInt(document.getElementById('maxFrames').value) || 12,
            min_time_gap: parseFloat(document.getElementById('minTimeGap').value) || 0.8,
            frame_gap: parseInt(document.getElementById('frameGap').value) || 5,
            min_frames_after_dedup: parseInt(document.getElementById('minFramesAfterDedup').value) || 3,
            enable_image_enhancement: document.getElementById('enableImageEnhancement').checked,
            enable_deduplication: document.getElementById('enableDeduplication').checked,
            
            // Advanced Frame Settings
            motion_weight: parseFloat(document.getElementById('motionWeight').value) || 3.0,
            scene_weight: parseFloat(document.getElementById('sceneWeight').value) || 1.5,
            color_weight: parseFloat(document.getElementById('colorWeight').value) || 0.5,
            edge_weight: parseFloat(document.getElementById('edgeWeight').value) || 2.0,
            content_frame_bar: parseFloat(document.getElementById('contentFrameBar').value) || 0.5,
            similarity_threshold: parseFloat(document.getElementById('similarityThreshold').value) || 0.95,
            maximum_dimension: parseInt(document.getElementById('maximumDimension').value) || 480
        };
    }
    
    async sendMessage() {
        if (!this.currentVideo || this.isProcessing) return;
        
        const messageInput = document.getElementById('messageInput');
        const message = messageInput.value.trim();
        
        if (!message) return;
        
        // Add user message
        this.addMessage('user', message);
        
        // Clear input
        messageInput.value = '';
        this.autoResizeTextarea();
        this.updateSendButtonState();
        
        // Show loading
        const loadingId = this.addLoadingMessage();
        this.isProcessing = true;
        
        try {
            const config = this.gatherConfiguration();
            
            // Create FormData for file upload
            const formData = new FormData();
            formData.append('video', this.currentVideo);
            formData.append('user_prompt', message);
            
            // Add configuration
            Object.keys(config).forEach(key => {
                if (config[key] !== undefined && config[key] !== null && config[key] !== '') {
                    formData.append(key, config[key]);
                }
            });
            
            const response = await fetch('/chat', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            
            // Remove loading message
            this.removeLoadingMessage(loadingId);
            
            if (!response.ok) {
                throw new Error(result.error || 'Analysis failed');
            }
            
            // Add assistant response
            this.addMessage('assistant', result.analysis, result.keyframes, result.processing_info, result.audio_analysis);
            
        } catch (error) {
            console.error('Chat failed:', error);
            this.removeLoadingMessage(loadingId);
            this.addMessage('error', `Error: ${error.message}`);
        } finally {
            this.isProcessing = false;
            this.updateSendButtonState();
        }
    }
    
    addMessage(type, content, keyframes = null, processingInfo = null, audio_analysis = null) {
        const messagesContainer = document.getElementById('chatMessages');
        
        // Hide welcome message if it exists
        const welcomeMessage = messagesContainer.querySelector('.welcome-message');
        if (welcomeMessage) {
            welcomeMessage.style.display = 'none';
        }
        
        const messageElement = document.createElement('div');
        
        if (type === 'system') {
            messageElement.className = 'system-message';
            messageElement.innerHTML = `
                <div class="system-message-content">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
                        <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0zM7 3v2H6V3h1zm1 3v7H7V6h1z"/>
                    </svg>
                    ${content}
                </div>
            `;
        } else if (type === 'error') {
            messageElement.className = 'error-message';
            messageElement.innerHTML = `
                <div class="error-message-content">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
                        <path d="M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0zM7 3h2v5H7V3zm0 6h2v2H7V9z"/>
                    </svg>
                    ${content}
                </div>
            `;
        } else {
            messageElement.className = `message ${type}`;
            
            const avatar = type === 'user' ? 'U' : 'AI';
            let processedContent = this.processMessageContent(content);
            if (audio_analysis) {
                const audioSectionId = `audio-section-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
                const processedAudioContent = this.processMessageContent(audio_analysis);
                
                processedContent += `
                    <br><br>
                    <div class="audio-analysis-wrapper">
                        <div onclick="toggleAudioAnalysis('${audioSectionId}')" style="cursor: pointer; display: inline-flex; align-items: center; gap: 8px;">
                            <svg id="icon-${audioSectionId}" width="16" height="16" viewBox="0 0 16 16" fill="currentColor" style="transform: rotate(-90deg); transition: transform 0.3s;">
                                <path d="M4.646 6.646a.5.5 0 0 1 .708 0L8 9.293l2.646-2.647a.5.5 0 0 1 .708.708l-3 3a.5.5 0 0 1-.708 0l-3-3a.5.5 0 0 1 0-.708z"/>
                            </svg>
                            <strong>Audio Analysis:</strong>
                        </div>
                        <div id="${audioSectionId}" style="display: none; margin-top: 8px;">
                            ${processedAudioContent}
                        </div>
                    </div>
                `;
            }

            let processingInfoHtml = '';
            if (processingInfo) {
                // Basic stats
                const basicStats = [
                    `Used ${processingInfo.processing_time || 0}s`,
                    `Extracted ${processingInfo.keyframes_count || 0} frames`
                ];
                
                if (processingInfo.audio_enabled) {
                    basicStats.push('Audio analyzed');
                }
                
                // Detailed token usage with simplified layout
                let tokenUsageHtml = '';
                if (processingInfo.usage) {
                    const usage = processingInfo.usage;
                    const visionUsage = usage.vision_usage || {};
                    const audioUsage = usage.audio_usage || {};
                    
                    const hasVisionTokens = visionUsage.total_tokens > 0;
                    const hasAudioTokens = audioUsage.total_tokens > 0;
                    
                    if (hasVisionTokens || hasAudioTokens) {
                        tokenUsageHtml = '<div class="token-usage"><strong>Token Usage Details:</strong>';
                        
                        // Side by side container for vision and audio
                        tokenUsageHtml += '<div class="token-sections-container">';
                        
                        // Vision tokens section
                        if (hasVisionTokens) {
                            tokenUsageHtml += '<div class="token-section-side">';
                            tokenUsageHtml += '<div class="token-section">';
                            tokenUsageHtml += '<div class="token-section-header">Vision Analysis</div>';
                            tokenUsageHtml += `<div class="token-row"><span>Input Tokens:</span><span><strong>${visionUsage.prompt_tokens.toLocaleString()}</strong></span></div>`;
                            
                            // Vision token details 
                            if (visionUsage.prompt_tokens_details) {
                                const details = visionUsage.prompt_tokens_details;
                                if (details.image_tokens && details.image_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Image Tokens:</span><span>${details.image_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.text_tokens && details.text_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Text Tokens:</span><span>${details.text_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.cached_tokens && details.cached_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Cached Tokens:</span><span>${details.cached_tokens.toLocaleString()}</span></div>`;
                                }
                            }
                            
                            tokenUsageHtml += `<div class="token-row"><span>Output Tokens:</span><span><strong>${visionUsage.completion_tokens.toLocaleString()}</strong></span></div>`;
                            
                            if (visionUsage.completion_tokens_details) {
                                const details = visionUsage.completion_tokens_details;
                                if (details.reasoning_tokens && details.reasoning_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Reasoning Tokens:</span><span>${details.reasoning_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.accepted_prediction_tokens && details.accepted_prediction_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Accepted Prediction:</span><span>${details.accepted_prediction_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.rejected_prediction_tokens && details.rejected_prediction_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Rejected Prediction:</span><span>${details.rejected_prediction_tokens.toLocaleString()}</span></div>`;
                                }
                            }
                            
                            tokenUsageHtml += `<div class="token-subtotal"><span>Vision Total:</span><span>${visionUsage.total_tokens.toLocaleString()}</span></div>`;
                            tokenUsageHtml += '</div>'; 
                            tokenUsageHtml += '</div>'; 
                        }

                        // Audio tokens section
                        if (hasAudioTokens) {
                            tokenUsageHtml += '<div class="token-section-side">';
                            tokenUsageHtml += '<div class="token-section">';
                            tokenUsageHtml += '<div class="token-section-header">Audio Analysis</div>';
                            tokenUsageHtml += `<div class="token-row"><span>Input Tokens:</span><span><strong>${audioUsage.prompt_tokens.toLocaleString()}</strong></span></div>`;
                            
                            // Audio token details 
                            if (audioUsage.prompt_tokens_details) {
                                const details = audioUsage.prompt_tokens_details;
                                if (details.audio_tokens && details.audio_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Audio Tokens:</span><span>${details.audio_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.text_tokens && details.text_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Text Tokens:</span><span>${details.text_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.cached_tokens && details.cached_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Cached Tokens:</span><span>${details.cached_tokens.toLocaleString()}</span></div>`;
                                }
                            }
                            
                            tokenUsageHtml += `<div class="token-row"><span>Output Tokens:</span><span><strong>${audioUsage.completion_tokens.toLocaleString()}</strong></span></div>`;
                            
                            if (audioUsage.completion_tokens_details) {
                                const details = audioUsage.completion_tokens_details;
                                if (details.audio_tokens && details.audio_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Audio Output:</span><span>${details.audio_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.text_tokens && details.text_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Text Output:</span><span>${details.text_tokens.toLocaleString()}</span></div>`;
                                }
                                if (details.reasoning_tokens && details.reasoning_tokens > 0) {
                                    tokenUsageHtml += `<div class="token-detail"><span>Reasoning Tokens:</span><span>${details.reasoning_tokens.toLocaleString()}</span></div>`;
                                }
                            }
                            
                            tokenUsageHtml += `<div class="token-subtotal"><span>Audio Total:</span><span>${audioUsage.total_tokens.toLocaleString()}</span></div>`;
                            tokenUsageHtml += '</div>'; 
                            tokenUsageHtml += '</div>'; 
                        }
                        
                        tokenUsageHtml += '</div>'; // Close token-sections-container
                        
                        // Grand total
                        const grandTotal = (visionUsage.total_tokens || 0) + (audioUsage.total_tokens || 0);
                        if (grandTotal > 0) {
                            tokenUsageHtml += `<div class="token-grand-total"><span>Grand Total:</span><span>${grandTotal.toLocaleString()} tokens</span></div>`;
                        }
                        
                        tokenUsageHtml += '</div>'; 
                    }
                }
                
                processingInfoHtml = `
                    <div class="processing-info">
                        <div class="processing-stats">
                            ${basicStats.map(stat => `<span>${stat}</span>`).join('')}
                        </div>
                        ${tokenUsageHtml}
                    </div>
                `;
            }
            
            let keyframesHtml = '';
            if (keyframes && keyframes.length > 0) {
                const keyframeSetId = `keyframes-${Date.now()}`;
                
                keyframesHtml = `
                    <div class="keyframes-section">
                        <h5>Extracted Keyframes (${keyframes.length})</h5>
                        <div class="keyframes-grid" data-keyframe-set="${keyframeSetId}">
                            ${keyframes.map((frame, index) => {
                                const imageSrc = frame.base64_image || frame.image || frame.src;
                                const timestamp = frame.timestamp || 0;
                                
                                return `
                                    <div class="keyframe-item" onclick="videoAnalyzerChat.openKeyframeFullscreen(${JSON.stringify(keyframes).replace(/"/g, '&quot;')}, ${index})">
                                        <img class="keyframe-image" 
                                            src="${imageSrc}" 
                                            alt="Keyframe ${index + 1}"
                                            loading="lazy">
                                        <div class="keyframe-info">
                                            <span class="frame-time">${this.formatTimestamp(timestamp)}</span>
                                        </div>
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    </div>
                `;
            }
            
            messageElement.innerHTML = `
                <div class="message-avatar">${avatar}</div>
                <div class="message-content">
                    <div class="message-text-wrapper">
                        ${processedContent}
                    </div>
                    ${processingInfoHtml}
                    ${keyframesHtml}
                </div>
            `;
        }
        
        messagesContainer.appendChild(messageElement);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        return messageElement.id = `message-${Date.now()}`;
    }
    
    processMessageContent(content) {
        // Convert markdown-style formatting to HTML
        return content
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.*?)\*/g, '<em>$1</em>')
            .replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>')
            .replace(/`(.*?)`/g, '<code>$1</code>')
            .replace(/\n/g, '<br>');
    }
    
    formatTimestamp(seconds) {
        const minutes = Math.floor(seconds / 60);
        const secs = (seconds % 60).toFixed(1);
        return `${minutes}:${secs.padStart(4, '0')}`;
    }
    
    addLoadingMessage() {
        const messagesContainer = document.getElementById('chatMessages');
        const loadingElement = document.createElement('div');
        const loadingId = `loading-${Date.now()}`;
        
        loadingElement.id = loadingId;
        loadingElement.className = 'message assistant loading-message';
        loadingElement.innerHTML = `
            <div class="message-avatar">AI</div>
            <div class="message-content">
                <div class="loading-content">
                    <div class="loading-spinner"></div>
                    <span>Analyzing your video...</span>
                </div>
            </div>
        `;
        
        messagesContainer.appendChild(loadingElement);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        return loadingId;
    }
    
    removeLoadingMessage(loadingId) {
        const loadingElement = document.getElementById(loadingId);
        if (loadingElement) {
            loadingElement.remove();
        }
    }
    
    toggleSettings() {
        const settingsPanel = document.getElementById('settingsPanel');
        const chatContainer = document.getElementById('chatContainer');
        
        this.settingsVisible = true;
        
        if (this.settingsVisible) {
            settingsPanel.classList.remove('hidden');
            chatContainer.classList.remove('settings-hidden');
        } else {
            settingsPanel.classList.add('hidden');
            chatContainer.classList.add('settings-hidden');
        }
        
        this.saveSettings();
    }
    
    clearChat() {
        const messagesContainer = document.getElementById('chatMessages');
        messagesContainer.innerHTML = '';
        this.showWelcomeMessage();
        
        // Also remove current video
        this.removeVideo();
    }
    
    saveSettings() {
        const settings = {
            azureEndpoint: document.getElementById('azureEndpoint').value,
            azureApiKey: document.getElementById('azureApiKey').value,
            llmModel: document.getElementById('llmModel').value,
            audioEndpoint: document.getElementById('audioEndpoint').value,
            audioApiKey: document.getElementById('audioApiKey').value,
            audioMainModel: document.getElementById('audioMainModel').value,
            audioV2Model: document.getElementById('audioV2Model').value,
            audioV3Model: document.getElementById('audioV3Model').value,
            systemPrompt: document.getElementById('systemPrompt').value,
            audioPrompt: document.getElementById('audioPrompt').value,
            settingsVisible: this.settingsVisible,
            panelWidth: parseInt(window.getComputedStyle(document.getElementById('settingsPanel')).width, 10)
        };
        
        localStorage.setItem('videoAnalyzerSettings', JSON.stringify(settings));
    }
    
    loadSettings() {
        try {
            const savedSettings = localStorage.getItem('videoAnalyzerSettings');
            if (!savedSettings) return;
            
            const settings = JSON.parse(savedSettings);
            
            // Load form values
            Object.keys(settings).forEach(key => {
                const element = document.getElementById(key);
                if (element && settings[key] !== undefined) {
                    element.value = settings[key];
                }
            });
            
            // Restore panel state
            if (settings.settingsVisible !== undefined) {
                this.settingsVisible = !settings.settingsVisible; // Will be toggled
                this.toggleSettings();
            }
            
            // Restore panel width
            if (settings.panelWidth) {
                const settingsPanel = document.getElementById('settingsPanel');
                settingsPanel.style.width = settings.panelWidth + 'px';
                document.documentElement.style.setProperty('--settings-panel-width', settings.panelWidth + 'px');
            }
            
            this.updateSendButtonState();
        } catch (error) {
            console.error('Failed to load settings:', error);
        }
    }
    
    exportSettings() {
        const config = this.gatherConfiguration();
        const dataStr = JSON.stringify(config, null, 2);
        const dataUri = 'data:application/json;charset=utf-8,'+ encodeURIComponent(dataStr);
        
        const exportFileDefaultName = 'video-analyzer-config.json';
        
        const linkElement = document.createElement('a');
        linkElement.setAttribute('href', dataUri);
        linkElement.setAttribute('download', exportFileDefaultName);
        linkElement.click();
    }
    
    importSettings(event) {
        const file = event.target.files[0];
        if (!file) return;
        
        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const config = JSON.parse(e.target.result);
                
                // Field mapping from export config to HTML element IDs
                const fieldMapping = {
                    // Azure OpenAI Configuration
                    'azure_endpoint': 'azureEndpoint',
                    'azure_api_key': 'azureApiKey',
                    'llm_model': 'llmModel',
                    
                    // Audio Configuration
                    'audio_endpoint': 'audioEndpoint',
                    'audio_api_key': 'audioApiKey',
                    'audio_main_model': 'audioMainModel',
                    'audio_v2_model': 'audioV2Model',
                    'audio_v3_model': 'audioV3Model',
                    'enable_audio_analysis': 'enableAudioAnalysis',
                    'enable_v2_audio': 'enableV2Audio',
                    'enable_v3_audio': 'enableV3Audio',
                    'audio_prompt': 'audioPrompt',
                    
                    // System Prompt
                    'system_prompt': 'systemPrompt',
                    
                    // Frame Extraction Settings
                    'max_frames': 'maxFrames',
                    'min_time_gap': 'minTimeGap',
                    'frame_gap': 'frameGap',
                    'min_frames_after_dedup': 'minFramesAfterDedup',
                    'enable_image_enhancement': 'enableImageEnhancement',
                    'enable_deduplication': 'enableDeduplication',
                    
                    // Advanced Frame Settings
                    'motion_weight': 'motionWeight',
                    'scene_weight': 'sceneWeight',
                    'color_weight': 'colorWeight',
                    'edge_weight': 'edgeWeight',
                    'content_frame_bar': 'contentFrameBar',
                    'similarity_threshold': 'similarityThreshold',
                    'maximum_dimension': 'maximumDimension'
                };
                
                // Load configuration into form
                Object.keys(config).forEach(key => {
                    const elementId = fieldMapping[key];
                    if (elementId) {
                        const element = document.getElementById(elementId);
                        if (element) {
                            if (element.type === 'checkbox') {
                                element.checked = config[key];
                            } else {
                                element.value = config[key];
                            }
                            
                            // Trigger change event to update UI (e.g., show audio config if enabled)
                            if (elementId === 'enableAudioAnalysis') {
                                element.dispatchEvent(new Event('change'));
                            }
                        }
                    }
                });
                
                this.updateSendButtonState();
                this.saveSettings();
                alert('Settings imported successfully!');
            } catch (error) {
                console.error('Import error:', error);
                alert('Failed to import settings: Invalid file format');
            }
        };
        reader.readAsText(file);
        event.target.value = '';
    }
}

// Global functions for HTML event handlers
let videoAnalyzerChat;

function removeVideo() {
    videoAnalyzerChat.removeVideo();
}

function toggleSettings() {
    videoAnalyzerChat.toggleSettings();
}

function clearChat() {
    videoAnalyzerChat.clearChat();
}

function sendMessage() {
    videoAnalyzerChat.sendMessage();
}

function exportSettings() {
    videoAnalyzerChat.exportSettings();
}

function importSettings(event) {
    videoAnalyzerChat.importSettings(event);
}

function toggleSection(header) {
    const content = header.nextElementSibling;
    const icon = header.querySelector('.collapse-icon');
    
    if (content.style.display === 'none') {
        content.style.display = 'block';
        icon.style.transform = 'rotate(180deg)';
    } else {
        content.style.display = 'none';
        icon.style.transform = 'rotate(0deg)';
    }
}

function toggleAudioAnalysis(sectionId) {
    const content = document.getElementById(sectionId);
    const icon = document.getElementById(`icon-${sectionId}`);
    
    if (content.style.display === 'none' || content.style.display === '') {
        content.style.display = 'block';
        icon.style.transform = 'rotate(0deg)'; 
    } else {
        content.style.display = 'none';
        icon.style.transform = 'rotate(-90deg)'; 
    }
}

function showConfigHelp() {
    document.getElementById('configHelpModal').style.display = 'flex';
}

function closeConfigHelp() {
    document.getElementById('configHelpModal').style.display = 'none';
}

window.onclick = function(event) {
    const modal = document.getElementById('configHelpModal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
}

// Initialize the app when the page loads
document.addEventListener('DOMContentLoaded', () => {
    videoAnalyzerChat = new VideoAnalyzerChat();
});

// Handle keyboard shortcuts
document.addEventListener('keydown', (e) => {
    // Don't interfere with fullscreen viewer keyboard navigation
    if (videoAnalyzerChat && videoAnalyzerChat.fullscreenViewer && videoAnalyzerChat.fullscreenViewer.classList.contains('active')) {
        return; // Let the fullscreen viewer handle it
    }
    
    // Escape key to close settings
    if (e.key === 'Escape') {
        const settingsPanel = document.getElementById('settingsPanel');
        if (settingsPanel && !settingsPanel.classList.contains('hidden')) {
            toggleSettings();
        }
    }
    
    // Ctrl/Cmd + Enter to send message
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        const messageInput = document.getElementById('messageInput');
        if (document.activeElement === messageInput) {
            sendMessage();
        }
    }
    
    // Ctrl/Cmd + K to clear chat
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        clearChat();
    }
});