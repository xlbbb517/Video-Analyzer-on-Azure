"""
EnhancedKeyFrameExtractor
Extraction Process:
1. Video Preprocessing: Extract video information, such as frame rate and resolution metadata.
2. Frame Analysis: Analyze the video frame by frame, calculating optical flow, scene changes, color histograms, and other metrics.
3. Key Frame Candidate Generation: Generate a set of key frame candidates based on temporal anchors and content frames.
4. Similarity Deduplication: Perform similarity detection on candidate frames to remove duplicates.
5. Candidate Merging: Merge candidate frames into the final candidate set.
6. Output Processing: Convert key frames to base64 encoding format for return.
"""

from time import time
import numpy as np
import cv2
from typing import List, Dict, Tuple, Optional
import base64
import io
from PIL import Image
from skimage.metrics import structural_similarity as ssim
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class EnhancedKeyFrameExtractor:
    
    def __init__(self):

        # Time segment definitions
        self.time_segments = [
            (0.0, 0.2, 'opening'),    
            (0.2, 0.4, 'early'),      
            (0.4, 0.6, 'middle'),     
            (0.6, 0.8, 'late'),       
            (0.8, 1.0, 'ending')      
        ]
    
    def get_video_info(self, video_path: str) -> Optional[Dict]:
        """Get video information"""      
        cap = cv2.VideoCapture(video_path)
        
        if not cap.isOpened():
            return None
        
        info = {
            'total_frames': int(cap.get(cv2.CAP_PROP_FRAME_COUNT)),
            'fps': cap.get(cv2.CAP_PROP_FPS),
            'width': int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
            'height': int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        }
        info['duration'] = info['total_frames'] / info['fps'] if info['fps'] > 0 else 0
        info['resolution_quality'] = info['width'] * info['height']
        
        cap.release()
        return info

    def _resize_frame_if_needed(self, frame: np.ndarray) -> np.ndarray:
        """Resize frame if needed based on maximum_dimension, maintaining aspect ratio"""
        height, width = frame.shape[:2]
        max_dim = max(height, width)
        
        if max_dim <= self.maximum_dimension:
            return frame
        
        scale_factor = self.maximum_dimension / max_dim
        return cv2.resize(frame, None, fx=scale_factor, fy=scale_factor)

    def extract_keyframes(self, video_path: str, max_frames: int = 12, min_time_gap: float = 0.8,
                 enable_image_enhancement: bool = False, min_frames_after_dedup: int = 3,
                 frame_gap: int = 5,motion_weight: float = 3.0,
                 scene_weight: float = 1.5, color_weight: float = 0.5, edge_weight: float = 2.0,
                 content_frame_bar: float = 0.5, enable_deduplication: bool = True,
                 similarity_threshold: float = 0.95, maximum_dimension: int = 480) -> List[Dict]:
        """Main keyframe extraction method
        Args:
            max_frames: Maximum number of keyframes
            min_time_gap: Minimum time gap (seconds)
            enable_image_enhancement: Whether to enable image enhancement
            min_frames_after_dedup: Minimum number of frames to keep after deduplication
            frame_gap: Frame analysis interval (how many frames to analyze at a time)
            motion_weight: Motion change weight
            scene_weight: Scene change weight
            color_weight: Color change weight
            edge_weight: Edge change weight
            content_frame_bar: Content frame selection ratio (between 0-1, indicating the proportion selected from candidate frames)
            enable_deduplication: Whether to enable similarity deduplication
            similarity_threshold: Similarity threshold (between 0-1)
            maximum_dimension: Maximum dimension limit (for downsampling during frame analysis)
        """
        self.max_frames = max_frames
        self.min_time_gap = min_time_gap
        self.enable_image_enhancement = enable_image_enhancement
        self.min_frames_after_dedup = min_frames_after_dedup
        self.frame_gap = frame_gap
        self.motion_weight = motion_weight
        self.scene_weight = scene_weight
        self.color_weight = color_weight
        self.edge_weight = edge_weight
        self.content_frame_bar = content_frame_bar
        self.enable_deduplication = enable_deduplication
        self.similarity_threshold = similarity_threshold
        self.maximum_dimension = maximum_dimension

        try:            
            # Phase 1: Get video information
            video_info = self.get_video_info(video_path)
            if not video_info:
                logger.info(f"Failed to get video information: {video_path}")
                return []
            
            video_info['video_path'] = video_path
            logger.info(f"Video information: {video_info['total_frames']} frames, {video_info['fps']:.2f} fps, {video_info['duration']:.2f} seconds, resolution: {video_info['width']}x{video_info['height']}")

            # Phase 2: Enhanced frame analysis
            frame_changes = self._enhanced_frame_analysis(video_path, video_info)
            
            if not frame_changes:
                logger.info("Frame analysis failed")
                return []
            logger.info(f"Phase 2 complete - Frame analysis: {len(frame_changes)} frame changes detected")

            # Phase 3: Intelligent frame selection
            selected_frames = self._intelligent_frame_selection(frame_changes, video_info)
            logger.info(f"Phase 3 complete - Frame selection: {len(selected_frames)} frames")

            # Phase 4: Extract and upload keyframes
            keyframe_data = self._extract_frames_as_base64(video_path, selected_frames)
            logger.info(f"Phase 4 complete - Frame extraction and conversion: {len(keyframe_data)} frames")

            return keyframe_data
            
        except Exception as e:
            logger.error(f"Keyframe extraction failed: {str(e)}")
            return []
    
    def _enhanced_frame_analysis(self, video_path: str, video_info: Dict) -> List[Dict]:
        """Enhanced frame analysis"""

        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return []

        ret, first_frame = cap.read()
        if not ret:
            cap.release()
            return []
        
        first_frame_resized = self._resize_frame_if_needed(first_frame)
        prev_gray = cv2.cvtColor(first_frame_resized, cv2.COLOR_BGR2GRAY)
        
        frame_changes = []
        
        frame_changes.append({
            'frame_idx': 0,
            'timestamp': 0.0,
            'change_score': 0.0,
            'scene_score': 0.0,
            'motion_score': 0.0,
            'color_score': 0.0,
            'time_segment': 'opening'
        })

        # Optical flow parameters
        flow_params = dict(
            pyr_scale=0.5,
            levels=3,
            winsize=15,
            iterations=3,
            poly_n=5,
            poly_sigma=1.2,
            flags=0
        )
        
        frame_count = 0
        prev_hsv = cv2.cvtColor(first_frame_resized, cv2.COLOR_BGR2HSV)
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            frame_count += 1
            
            if frame_count % self.frame_gap == 0:
                timestamp = frame_count / video_info['fps']
                
                frame_resized = self._resize_frame_if_needed(frame)
                curr_gray = cv2.cvtColor(frame_resized, cv2.COLOR_BGR2GRAY)
                curr_hsv = cv2.cvtColor(frame_resized, cv2.COLOR_BGR2HSV)

                try:
                    flow = cv2.calcOpticalFlowFarneback(prev_gray, curr_gray, None, **flow_params)
                    magnitude, angle = cv2.cartToPolar(flow[..., 0], flow[..., 1])
                    motion_score = np.mean(magnitude) * 10  
                except:
                    motion_score = 0.0

                pixel_diff = cv2.absdiff(prev_gray, curr_gray)
                scene_score = np.mean(pixel_diff)
                
                hist_prev = cv2.calcHist([prev_hsv], [0, 1], None, [50, 60], [0, 180, 0, 256])
                hist_curr = cv2.calcHist([curr_hsv], [0, 1], None, [50, 60], [0, 180, 0, 256])
                hist_prev = cv2.normalize(hist_prev, hist_prev).flatten()
                hist_curr = cv2.normalize(hist_curr, hist_curr).flatten()
                color_score = cv2.compareHist(hist_prev, hist_curr, cv2.HISTCMP_CHISQR)
                
                edges_prev = cv2.Canny(prev_gray, 50, 150)
                edges_curr = cv2.Canny(curr_gray, 50, 150)
                edge_diff = cv2.absdiff(edges_prev, edges_curr)
                edge_score = np.sum(edge_diff) / (edge_diff.shape[0] * edge_diff.shape[1]) * 100

                time_segment = self._get_time_segment(timestamp, video_info['duration'])

                # Comprehensive change score
                base_score = (
                    motion_score * self.motion_weight +     # Motion weight
                    scene_score * self.scene_weight +       # Scene change
                    color_score * self.color_weight +       # Color change
                    edge_score * self.edge_weight           # Edge change
                )
                
                final_score = base_score

                frame_changes.append({
                    'frame_idx': frame_count,
                    'timestamp': timestamp,
                    'change_score': final_score,
                    'scene_score': scene_score,
                    'motion_score': motion_score,
                    'color_score': color_score,
                    'edge_score': edge_score,
                    'time_segment': time_segment
                })

                prev_gray = curr_gray
                prev_hsv = curr_hsv

            if frame_count % 100 == 0:
                logger.info(f"Already analyzed {frame_count}/{video_info['total_frames']} frames...")

        cap.release()
        return frame_changes

    def _calculate_frame_similarity(self, frame1: np.ndarray, frame2: np.ndarray) -> float:
        """Calculate the similarity between two frames"""
        try:
            # Resize frames to ensure consistency
            frame1_resized = self._resize_frame_if_needed(frame1)
            frame2_resized = self._resize_frame_if_needed(frame2)
            
            gray1 = cv2.cvtColor(frame1_resized, cv2.COLOR_BGR2GRAY)
            gray2 = cv2.cvtColor(frame2_resized, cv2.COLOR_BGR2GRAY)
            
            if gray1.shape != gray2.shape:
                h = max(gray1.shape[0], gray2.shape[0])
                w = max(gray1.shape[1], gray2.shape[1])
                gray1 = cv2.resize(gray1, (w, h))
                gray2 = cv2.resize(gray2, (w, h))

            similarity = ssim(gray1, gray2)
            return similarity
        except:
            return 0.0

    def _select_time_anchors(self, frame_changes: List[Dict], video_info: Dict) -> List[Dict]:
        """Select time anchors"""
        anchors = []
        
        for start_ratio, end_ratio, segment_name in self.time_segments:
            start_time = start_ratio * video_info['duration']
            end_time = end_ratio * video_info['duration']
            
            segment_frames = [f for f in frame_changes 
                             if start_time <= f['timestamp'] < end_time]
            
            if segment_frames:
                best_frame = max(segment_frames, key=lambda x: x['change_score'])
                anchors.append(best_frame)
        
        return anchors
    
    def _calculate_adaptive_thresholds(self, frame_changes: List[Dict]) -> Dict[str, float]:
        """Calculate adaptive thresholds"""
        if not frame_changes:
            return {'high_change_threshold': 15.0}

        # Extract all change scores
        change_scores = [f['change_score'] for f in frame_changes if f['change_score'] > 0]
        
        if not change_scores:
            return {'high_change_threshold': 15.0}

        change_stats = {
            'mean': np.mean(change_scores),
            'std': np.std(change_scores),
            'median': np.median(change_scores),
            'q25': np.percentile(change_scores, 25),
            'q75': np.percentile(change_scores, 75),
            'q90': np.percentile(change_scores, 90),
            'q95': np.percentile(change_scores, 95),
            'max': np.max(change_scores),
            'min': np.min(change_scores)
        }
        
        thresholds = {'high_change_threshold': change_stats['q75']}
        
        return thresholds
    
    def _select_content_frames(self, frame_changes: List[Dict], existing_frames: List[Dict], 
                              adaptive_thresholds: Dict = None) -> List[Dict]:
        """Select content change frames"""
        if adaptive_thresholds is None:
            adaptive_thresholds = self._calculate_adaptive_thresholds(frame_changes)
        
        existing_timestamps = {f['timestamp'] for f in existing_frames}
        high_change_threshold = adaptive_thresholds['high_change_threshold']
        
        candidates = []
        for frame in frame_changes:
            if any(abs(frame['timestamp'] - ts) < self.min_time_gap for ts in existing_timestamps):
                continue
        
            if (frame['change_score'] > high_change_threshold):
                candidates.append(frame)

        candidates.sort(key=lambda x: x['change_score'], reverse=True)

        if len(candidates) > 0:
            percent_count = min(int(len(candidates)*self.content_frame_bar), len(candidates))  
            candidates = candidates[:percent_count]

        selected = []
        for candidate in candidates:
            if all(abs(candidate['timestamp'] - s['timestamp']) >= self.min_time_gap 
                    for s in selected + existing_frames):
                 selected.append(candidate)
        
        return selected
    
    def _intelligent_frame_selection(self, frame_changes: List[Dict], video_info: Dict) -> List[Dict]:
        """Intelligent frame selection"""
        adaptive_thresholds = self._calculate_adaptive_thresholds(frame_changes)
        time_anchors = self._select_time_anchors(frame_changes, video_info)
        content_frames = self._select_content_frames(frame_changes, time_anchors, adaptive_thresholds)
        all_candidates = time_anchors + content_frames
        logger.info(f"Candidate frames merged: anchor {len(time_anchors)} + content {len(content_frames)} = {len(all_candidates)}")
        if self.enable_deduplication:
            video_path = video_info.get('video_path', '')
            if video_path:
                deduplicated_candidates = self._deduplicate_similar_frames(all_candidates, video_path)
            else:
                logger.info("video_path is missing, skipping similarity deduplication")
                deduplicated_candidates = all_candidates
        else:
            deduplicated_candidates = all_candidates
        final_frames = self._final_selection(deduplicated_candidates)
        logger.info(f"Frame selection complete: candidates {len(deduplicated_candidates)} → final {len(final_frames)}")

        return final_frames

    def _deduplicate_similar_frames(self, candidates: List[Dict], video_path: str) -> List[Dict]:
        """Remove similar candidate frames - optional"""
        if len(candidates) <= 1:
            return candidates

        logger.info(f"Starting deduplication: {len(candidates)} candidate frames")
        candidates.sort(key=lambda x: x['timestamp'])
        cap = cv2.VideoCapture(video_path)
        
        if not cap.isOpened():
            logger.info("Cannot open video for similarity calculation, skipping")
            return candidates
    
        frame_cache = {}
        for candidate in candidates:
            frame_idx = candidate['frame_idx']
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            if ret:
                resized_frame = self._resize_frame_if_needed(frame)
                frame_cache[frame_idx] = resized_frame
        
        cap.release()
        filtered = []
        last_progress_time = time()
        for candidate in candidates:
            frame_idx = candidate['frame_idx']
            if frame_idx not in frame_cache: 
                logger.info(f"Skipping uncached frame: {frame_idx}")
                continue
        
            current_frame = frame_cache[frame_idx]
            is_similar = False
            
            for existing in filtered:
                existing_idx = existing['frame_idx']
                if existing_idx in frame_cache:
                    similarity = self._calculate_frame_similarity(current_frame, frame_cache[existing_idx])
                    if similarity > self.similarity_threshold:
                        is_similar = True
                        if candidate['change_score'] > existing['change_score']:
                            filtered.remove(existing)
                            filtered.append(candidate)
                            logger.info(f"Replacing frame: t={existing['timestamp']:.2f}s → t={candidate['timestamp']:.2f}s")
                        else:
                            logger.info(f"Removing similar frame: t={candidate['timestamp']:.2f}s")
                        break
            
            if not is_similar:
                filtered.append(candidate)

            current_time = time()
            if current_time - last_progress_time > 15:
                logger.info(f"Deduplication in progress...")
                last_progress_time = current_time

        if len(filtered) < self.min_frames_after_dedup:
            remaining_candidates = [c for c in candidates if c not in filtered]
            remaining_candidates.sort(key=lambda x: x['change_score'], reverse=True)
            
            needed_frames = self.min_frames_after_dedup - len(filtered)
            additional_frames = remaining_candidates[:needed_frames]
            
            filtered.extend(additional_frames)
            logger.info(f"Supplementing frames to meet minimum retention: added {len(additional_frames)} frames, current total: {len(filtered)}")

        filtered.sort(key=lambda x: x['timestamp'])
        return filtered
    
    def _final_selection(self, candidates: List[Dict]) -> List[Dict]:
        """Final selection"""
        if len(candidates) <= self.max_frames:
            candidates.sort(key=lambda x: x['timestamp'])
            return candidates
        candidates.sort(key=lambda x: x['timestamp'])
        deduplicated = []
        i = 0
        while i < len(candidates):
            current_group = [candidates[i]]
            j = i + 1
            while j < len(candidates) and candidates[j]['timestamp'] - candidates[i]['timestamp'] < self.min_time_gap:
                current_group.append(candidates[j])
                j += 1
            best = max(current_group, key=lambda x: x['change_score'])
            deduplicated.append(best)
            i = j

        if len(deduplicated) > self.max_frames:
            deduplicated.sort(key=lambda x: x['change_score'], reverse=True)
            deduplicated = deduplicated[:self.max_frames]

        deduplicated.sort(key=lambda x: x['timestamp'])
        return deduplicated

    def _extract_frames_as_base64(self, video_path: str, selected_frames: List[Dict]) -> List[Dict]:
        """Extract selected frames and convert to base64 encoding"""
        keyframes = []
        
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return []
        
        try:
            for i, frame_info in enumerate(selected_frames):
                frame_number = frame_info['frame_idx']
                timestamp = frame_info['timestamp']
                cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)
                ret, frame = cap.read() 
                if not ret:
                    continue

                if self.enable_image_enhancement:
                    enhanced_frame = self._enhance_frame_quality(frame)
                    frame = enhanced_frame
            
                base64_image = self.frame_to_base64(frame)
                if base64_image:
                    keyframes.append({
                        'frame_number': frame_number,
                        'timestamp': timestamp,
                        'base64_image': base64_image
                    })
            
        finally:
            cap.release()
        
        return keyframes
    
    def _get_time_segment(self, timestamp: float, duration: float) -> str:
        """Get time segment"""
        ratio = timestamp / duration if duration > 0 else 0
        
        for start_ratio, end_ratio, segment_name in self.time_segments:
            if start_ratio <= ratio <= end_ratio:
                return segment_name
        
        return 'unknown'
    
    def frame_to_base64(self, frame: np.ndarray, format: str = 'JPEG', quality: int = 85) -> str:
        """Convert OpenCV frame to base64 encoding"""
        try:
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            pil_image = Image.fromarray(frame_rgb)
            buffer = io.BytesIO()
            if format.upper() == 'JPEG':
                pil_image.save(buffer, format='JPEG', quality=quality, optimize=True)
            else:
                pil_image.save(buffer, format=format)
            buffer.seek(0)
            base64_str = base64.b64encode(buffer.getvalue()).decode('utf-8')
            
            return f"data:image/{format.lower()};base64,{base64_str}"
            
        except Exception as e:
            return ""
        
    def _detect_frame_clarity(self, frame: np.ndarray) -> Dict[str, float]:
        """Detect frame clarity metrics"""
        try:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
            sobelx = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
            sobely = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
            sobel_magnitude = np.sqrt(sobelx**2 + sobely**2)
            sobel_mean = np.mean(sobel_magnitude)
            contrast = np.std(gray)
            brightness = np.mean(gray)
            
            return {
                'clarity_score': laplacian_var,
                'edge_strength': sobel_mean,
                'contrast': contrast,
                'brightness': brightness,
                'is_clear': laplacian_var > 100.0,  # Clear threshold
                'is_dark': brightness < 50,         # Dark threshold
                'is_bright': brightness > 200,      # Bright threshold
                'is_low_contrast': contrast < 30    # Low contrast threshold
            }
        except Exception as e:
            logger.info(f"Frame clarity detection failed: {e}")
            return {
                'clarity_score': 0.0,
                'edge_strength': 0.0,
                'contrast': 0.0,
                'brightness': 128.0,
                'is_clear': False,
                'is_dark': False,
                'is_bright': False,
                'is_low_contrast': True
            }

    def _enhance_frame_quality(self, frame: np.ndarray, clarity_info: Dict = None) -> Tuple[np.ndarray, Dict]:
        """Enhance image quality - for scenes like night, backlight, blur, etc."""
        if clarity_info is None:
            clarity_info = self._detect_frame_clarity(frame)
        
        enhanced = frame.copy()
        
        try:
            if clarity_info['is_dark']:
                gamma = 0.7  
                inv_gamma = 1.0 / gamma
                table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in range(256)]).astype("uint8")
                enhanced = cv2.LUT(enhanced, table)
                
            elif clarity_info['is_bright']:
                gamma = 1.3  
                inv_gamma = 1.0 / gamma
                table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in range(256)]).astype("uint8")
                enhanced = cv2.LUT(enhanced, table)
            
            if clarity_info['is_low_contrast'] or clarity_info['contrast'] < 40:
                lab = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)
                l, a, b = cv2.split(lab)
                clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8,8))
                l = clahe.apply(l)
                enhanced = cv2.merge([l, a, b])
                enhanced = cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)

            if not clarity_info['is_clear'] or clarity_info['clarity_score'] < 150:
                if clarity_info['clarity_score'] < 50:
                    kernel = np.array([[-1,-1,-1,-1,-1],
                                     [-1,2,2,2,-1],
                                     [-1,2,8,2,-1],
                                     [-1,2,2,2,-1],
                                     [-1,-1,-1,-1,-1]]) / 8.0
                    strength = 0.8
                elif clarity_info['clarity_score'] < 100:
                    kernel = np.array([[-1,-1,-1],
                                     [-1,9,-1],
                                     [-1,-1,-1]])
                    strength = 0.6
                else:
                    kernel = np.array([[0,-1,0],
                                     [-1,5,-1],
                                     [0,-1,0]])
                    strength = 0.4
                
                sharpened = cv2.filter2D(enhanced, -1, kernel)
                enhanced = cv2.addWeighted(enhanced, 1-strength, sharpened, strength, 0)
            
            if clarity_info['is_dark'] and clarity_info['brightness'] < 40:
                enhanced = cv2.bilateralFilter(enhanced, 9, 75, 75)
            
            if clarity_info['brightness'] < 60 or clarity_info['brightness'] > 180:
                lab = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)
                avg_a = np.average(lab[:, :, 1])
                avg_b = np.average(lab[:, :, 2])
                lab[:, :, 1] = lab[:, :, 1] - ((avg_a - 128) * 0.3)
                lab[:, :, 2] = lab[:, :, 2] - ((avg_b - 128) * 0.3)
                
                enhanced = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
            
        except Exception as e:
            logger.info(f"Image enhancement processing failed: {e}")
            return frame
        
        return enhanced