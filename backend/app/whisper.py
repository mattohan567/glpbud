"""
OpenAI Whisper integration for audio transcription.
Supports multiple languages including Romanian.
"""

import os
import base64
import tempfile
import logging
from typing import Optional
from openai import OpenAI

logger = logging.getLogger(__name__)

# Initialize OpenAI client
client = None

def init_whisper():
    """Initialize OpenAI client for Whisper API."""
    global client
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        logger.warning("OPENAI_API_KEY not found - audio transcription will not be available")
        return False

    try:
        client = OpenAI(api_key=api_key)
        logger.info("OpenAI Whisper client initialized successfully")
        return True
    except Exception as e:
        logger.error(f"Failed to initialize OpenAI client: {e}")
        return False

def transcribe_audio(audio_base64: str, language: Optional[str] = None) -> Optional[str]:
    """
    Transcribe audio using OpenAI Whisper API.

    Args:
        audio_base64: Base64 encoded audio data
        language: Optional language hint (e.g., 'ro' for Romanian, 'en' for English)
                 If not provided, Whisper will auto-detect

    Returns:
        Transcribed text or None if transcription fails
    """
    global client

    # Initialize client if needed
    if client is None:
        if not init_whisper():
            logger.error("Whisper not available - returning placeholder")
            return "[Audio transcription not available - OpenAI API key missing]"

    try:
        # Decode base64 audio
        audio_bytes = base64.b64decode(audio_base64)

        # Create temporary file for audio (Whisper API requires file)
        with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as temp_file:
            temp_file.write(audio_bytes)
            temp_file_path = temp_file.name

        try:
            # Open the file for transcription
            with open(temp_file_path, "rb") as audio_file:
                # Call Whisper API
                # Note: whisper-1 model supports 99+ languages including Romanian
                transcript = client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    language=language,  # Optional language hint
                    response_format="text"
                )

                logger.info(f"Audio transcribed successfully: {len(transcript)} chars")
                return transcript

        finally:
            # Clean up temp file
            try:
                os.unlink(temp_file_path)
            except:
                pass

    except Exception as e:
        logger.error(f"Error transcribing audio: {e}")
        return None

def transcribe_meal_audio(audio_base64: str, hints: Optional[str] = None) -> str:
    """
    Transcribe meal description audio and prepare for nutrition parsing.

    Args:
        audio_base64: Base64 encoded audio data
        hints: Optional hints about the meal

    Returns:
        Transcribed text ready for nutrition parsing
    """
    # Transcribe audio (auto-detect language)
    transcript = transcribe_audio(audio_base64)

    if not transcript:
        # Fallback if transcription fails
        return hints or "Unable to transcribe audio"

    # Combine transcript with any hints
    if hints:
        return f"{transcript}. Additional info: {hints}"

    return transcript