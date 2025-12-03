"""
Speaker Verification API Backend
A Flask API for speaker recognition with audio registration
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from speechbrain.inference.speaker import SpeakerRecognition
import os
import tempfile
from werkzeug.utils import secure_filename
from datetime import datetime
import json
from pydub import AudioSegment


# Initialize Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for Flutter frontend

# Configuration
ALLOWED_EXTENSIONS = {'wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac'}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB max file size
REGISTERED_AUDIOS_DIR = 'registered-audios'

# Create registered audios directory if it doesn't exist
os.makedirs(REGISTERED_AUDIOS_DIR, exist_ok=True)

# Load the SpeechBrain model (loads once at startup)
print("Loading SpeechBrain model...")
verification_model = SpeakerRecognition.from_hparams(
    source="speechbrain/spkrec-ecapa-voxceleb",
    savedir="pretrained_models/spkrec-ecapa-voxceleb"
)
print("Model loaded successfully!")


def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def get_confidence_level(score):
    """
    Convert numerical score to human-readable confidence level
    
    Parameters:
    -----------
    score : float
        Cosine similarity score (0 to 1)
    
    Returns:
    --------
    str : Confidence level description
    """
    if score > 0.7:
        return "Very High"
    elif score > 0.5:
        return "High"
    elif score > 0.35:
        return "Moderate"
    elif score > 0.25:
        return "Low"
    else:
        return "Very Low"


def get_registered_audios():
    """
    Get list of all registered audio files
    
    Returns:
    --------
    list : List of registered audio filenames
    """
    if not os.path.exists(REGISTERED_AUDIOS_DIR):
        return []
    
    return [f for f in os.listdir(REGISTERED_AUDIOS_DIR) 
            if os.path.isfile(os.path.join(REGISTERED_AUDIOS_DIR, f)) 
            and allowed_file(f)]


def load_metadata():
    """Load metadata about registered speakers"""
    metadata_path = os.path.join(REGISTERED_AUDIOS_DIR, 'metadata.json')
    if os.path.exists(metadata_path):
        with open(metadata_path, 'r') as f:
            return json.load(f)
    return {}


def save_metadata(metadata):
    """Save metadata about registered speakers"""
    metadata_path = os.path.join(REGISTERED_AUDIOS_DIR, 'metadata.json')
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    registered_count = len(get_registered_audios())
    return jsonify({
        'status': 'healthy',
        'message': 'Speaker Verification API is running',
        'registered_speakers': registered_count
    }), 200


@app.route('/verify', methods=['POST'])
def verify_speakers():
    """
    Main endpoint for speaker verification
    
    Expects:
    --------
    POST request with multipart/form-data containing:
    - audio1: First audio file
    - audio2: Second audio file
    - threshold (optional): Custom threshold (default: 0.25)
    
    Returns:
    --------
    JSON response with similarity score and prediction
    """
    
    # Validate request has files
    if 'audio1' not in request.files or 'audio2' not in request.files:
        return jsonify({
            'error': 'Missing audio files',
            'message': 'Both audio1 and audio2 files are required'
        }), 400
    
    audio1 = request.files['audio1']
    audio2 = request.files['audio2']
    
    # Validate files are not empty
    if audio1.filename == '' or audio2.filename == '':
        return jsonify({
            'error': 'Empty filename',
            'message': 'Both files must have valid filenames'
        }), 400
    
    # Validate file extensions
    if not (allowed_file(audio1.filename) and allowed_file(audio2.filename)):
        return jsonify({
            'error': 'Invalid file type',
            'message': f'Allowed types: {", ".join(ALLOWED_EXTENSIONS)}'
        }), 400
    
    # Get optional threshold parameter (default: 0.25)
    threshold = float(request.form.get('threshold', 0.25))
    
    # Validate threshold range
    if not (0.0 <= threshold <= 1.0):
        return jsonify({
            'error': 'Invalid threshold',
            'message': 'Threshold must be between 0.0 and 1.0'
        }), 400
    
    try:
        # Create temporary directory for audio files
        with tempfile.TemporaryDirectory() as temp_dir:
            # Save uploaded files to temporary location
            audio1_path = os.path.join(temp_dir, secure_filename(audio1.filename))
            audio2_path = os.path.join(temp_dir, secure_filename(audio2.filename))
            
            audio1.save(audio1_path)
            audio2.save(audio2_path)
            
            # Perform speaker verification
            score, _ = verification_model.verify_files(audio1_path, audio2_path)
            score_value = float(score.item())
            
            # Make prediction based on threshold
            same_speaker = score_value > threshold
            
            # Get confidence level
            confidence = get_confidence_level(score_value)
            
            # Prepare response
            response = {
                'success': True,
                'score': round(score_value, 4),
                'threshold': threshold,
                'same_speaker': same_speaker,
                'confidence': confidence,
                'interpretation': {
                    'message': f"The speakers are {'LIKELY the same person' if same_speaker else 'LIKELY different people'}",
                    'certainty': confidence
                }
            }
            
            return jsonify(response), 200
    
    except Exception as e:
        # Handle any errors during processing
        return jsonify({
            'error': 'Processing failed',
            'message': str(e)
        }), 500


@app.route('/register', methods=['POST'])
def register_audio():
    """
    Register a new speaker audio to the database
    Automatically converts AAC to WAV format
    """
    
    if 'audio' not in request.files:
        return jsonify({
            'error': 'Missing audio file',
            'message': 'Audio file is required'
        }), 400
    
    audio = request.files['audio']
    
    if audio.filename == '':
        return jsonify({
            'error': 'Empty filename',
            'message': 'Audio file must have a valid filename'
        }), 400
    
    if not allowed_file(audio.filename):
        return jsonify({
            'error': 'Invalid file type',
            'message': f'Allowed types: {", ".join(ALLOWED_EXTENSIONS)}'
        }), 400
    
    speaker_name = request.form.get('speaker_name', '')
    
    try:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        original_filename = secure_filename(audio.filename)
        file_extension = original_filename.rsplit('.', 1)[1].lower()
        
        # Create filename
        if speaker_name:
            safe_speaker_name = secure_filename(speaker_name)
            base_filename = f"{safe_speaker_name}_{timestamp}"
        else:
            base_filename = f"speaker_{timestamp}"
        
        # Always save as WAV for consistency
        filename = f"{base_filename}.wav"
        filepath = os.path.join(REGISTERED_AUDIOS_DIR, filename)
        
        # Check if conversion is needed
        if file_extension == 'aac':
            # Save AAC temporarily
            with tempfile.NamedTemporaryFile(suffix='.aac', delete=False) as temp_aac:
                audio.save(temp_aac.name)
                temp_aac_path = temp_aac.name
            
            try:
                # Convert AAC to WAV
                audio_segment = AudioSegment.from_file(temp_aac_path, format='aac')
                # Export as WAV with standard settings (16kHz mono is ideal for speaker recognition)
                audio_segment = audio_segment.set_frame_rate(16000).set_channels(1)
                audio_segment.export(filepath, format='wav')
            finally:
                # Clean up temporary AAC file
                os.unlink(temp_aac_path)
        elif file_extension == 'wav':
            # Already WAV, just save it
            audio.save(filepath)
        else:
            # Convert other formats to WAV
            with tempfile.NamedTemporaryFile(suffix=f'.{file_extension}', delete=False) as temp_file:
                audio.save(temp_file.name)
                temp_path = temp_file.name
            
            try:
                audio_segment = AudioSegment.from_file(temp_path, format=file_extension)
                audio_segment = audio_segment.set_frame_rate(16000).set_channels(1)
                audio_segment.export(filepath, format='wav')
            finally:
                os.unlink(temp_path)
        
        # Update metadata
        metadata = load_metadata()
        metadata[filename] = {
            'speaker_name': speaker_name or 'Unknown',
            'original_filename': original_filename,
            'original_format': file_extension,
            'registered_at': datetime.now().isoformat(),
            'file_size': os.path.getsize(filepath)
        }
        save_metadata(metadata)
        
        return jsonify({
            'success': True,
            'message': 'Audio registered successfully',
            'filename': filename,
            'speaker_name': speaker_name or 'Unknown',
            'original_format': file_extension,
            'converted_to': 'wav',
            'registered_at': metadata[filename]['registered_at']
        }), 201
    
    except Exception as e:
        return jsonify({
            'error': 'Registration failed',
            'message': str(e)
        }), 500

@app.route('/registered', methods=['GET'])
def list_registered():
    """
    List all registered speaker audios
    
    Returns:
    --------
    JSON response with list of registered speakers
    """
    try:
        audios = get_registered_audios()
        metadata = load_metadata()
        
        registered_list = []
        for filename in audios:
            info = metadata.get(filename, {})
            registered_list.append({
                'filename': filename,
                'speaker_name': info.get('speaker_name', 'Unknown'),
                'registered_at': info.get('registered_at', 'Unknown'),
                'file_size': info.get('file_size', 0)
            })
        
        return jsonify({
            'success': True,
            'count': len(registered_list),
            'registered_speakers': registered_list
        }), 200
    
    except Exception as e:
        return jsonify({
            'error': 'Failed to list registered speakers',
            'message': str(e)
        }), 500


@app.route('/delete/<filename>', methods=['DELETE'])
def delete_registered(filename):
    """
    Delete a registered speaker audio
    
    Parameters:
    -----------
    filename : str
        Name of the file to delete
    
    Returns:
    --------
    JSON response with deletion confirmation
    """
    try:
        # Secure the filename
        safe_filename = secure_filename(filename)
        filepath = os.path.join(REGISTERED_AUDIOS_DIR, safe_filename)
        
        if not os.path.exists(filepath):
            return jsonify({
                'error': 'File not found',
                'message': f'No registered audio found with filename: {filename}'
            }), 404
        
        # Delete the file
        os.remove(filepath)
        
        # Update metadata
        metadata = load_metadata()
        if safe_filename in metadata:
            del metadata[safe_filename]
            save_metadata(metadata)
        
        return jsonify({
            'success': True,
            'message': 'Audio deleted successfully',
            'filename': safe_filename
        }), 200
    
    except Exception as e:
        return jsonify({
            'error': 'Deletion failed',
            'message': str(e)
        }), 500


@app.route('/verify-against-registered', methods=['POST'])
def verify_against_registered():
    """
    Compare uploaded audio against ALL registered speakers
    
    Expects:
    --------
    POST request with multipart/form-data containing:
    - audio: Audio file to verify
    - threshold (optional): Custom threshold (default: 0.25)
    - top_n (optional): Return only top N matches (default: all)
    
    Returns:
    --------
    JSON response with array of comparison results, sorted by score
    """
    
    if 'audio' not in request.files:
        return jsonify({
            'error': 'Missing audio file',
            'message': 'Audio file is required'
        }), 400
    
    audio = request.files['audio']
    
    if audio.filename == '':
        return jsonify({
            'error': 'Empty filename',
            'message': 'Audio file must have a valid filename'
        }), 400
    
    if not allowed_file(audio.filename):
        return jsonify({
            'error': 'Invalid file type',
            'message': f'Allowed types: {", ".join(ALLOWED_EXTENSIONS)}'
        }), 400
    
    threshold = float(request.form.get('threshold', 0.25))
    top_n = request.form.get('top_n', None)
    if top_n:
        top_n = int(top_n)
    
    # Get registered audios
    registered_audios = get_registered_audios()
    
    if not registered_audios:
        return jsonify({
            'error': 'No registered speakers',
            'message': 'No speakers have been registered yet. Use /register endpoint first.'
        }), 404
    
    try:
        metadata = load_metadata()
        results = []
        
        with tempfile.TemporaryDirectory() as temp_dir:
            # Save uploaded audio
            test_path = os.path.join(temp_dir, secure_filename(audio.filename))
            audio.save(test_path)
            
            # Compare against each registered audio
            for registered_filename in registered_audios:
                registered_path = os.path.join(REGISTERED_AUDIOS_DIR, registered_filename)
                
                # Verify
                score, _ = verification_model.verify_files(test_path, registered_path)
                score_value = float(score.item())
                
                speaker_info = metadata.get(registered_filename, {})
                
                results.append({
                    'filename': registered_filename,
                    'speaker_name': speaker_info.get('speaker_name', 'Unknown'),
                    'score': round(score_value, 4),
                    'same_speaker': score_value > threshold,
                    'confidence': get_confidence_level(score_value)
                })
        
        # Sort by score (highest first)
        results.sort(key=lambda x: x['score'], reverse=True)
        
        # Limit to top N if requested
        if top_n:
            results = results[:top_n]
        
        # Find best match
        best_match = results[0] if results else None
        
        return jsonify({
            'success': True,
            'threshold': threshold,
            'total_registered': len(registered_audios),
            'best_match': best_match,
            'all_results': results
        }), 200
    
    except Exception as e:
        return jsonify({
            'error': 'Verification failed',
            'message': str(e)
        }), 500


if __name__ == '__main__':
    # Run the Flask development server
    print("\n" + "="*60)
    print("🎤 Speaker Verification API Server")
    print("="*60)
    print(f"Server starting on http://localhost:5000")
    print(f"Registered audios directory: {REGISTERED_AUDIOS_DIR}")
    print(f"\nEndpoints available:")
    print(f"  - GET    /health                     : Health check")
    print(f"  - POST   /verify                     : Compare two audio files")
    print(f"  - POST   /register                   : Register a new speaker")
    print(f"  - GET    /registered                 : List all registered speakers")
    print(f"  - DELETE /delete/<filename>          : Delete a registered speaker")
    print(f"  - POST   /verify-against-registered  : Compare against all registered")
    print("="*60 + "\n")
    
    # Run in debug mode for development
    app.run(host='0.0.0.0', port=5000, debug=True)