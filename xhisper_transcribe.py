#!/usr/bin/env python3
"""
xhisper transcription module using faster-whisper
Transcribes audio files locally using Whisper models.
"""

import sys
import argparse
import logging
from pathlib import Path

# Configure logging to suppress verbose output
logging.getLogger("faster_whisper").setLevel(logging.WARNING)

def transcribe_file(
    audio_path: str,
    model_size: str = "base",
    device: str = "auto",
    language: str = None,
    prompt: str = None,
    multilingual: bool = False,
) -> str:
    """
    Transcribe an audio file using faster-whisper.

    Args:
        audio_path: Path to the audio file (WAV, MP3, etc.)
        model_size: Model size (tiny, base, small, medium, large-v1, large-v2, large-v3)
        device: Device to use (auto, cpu, cuda)
        language: Language code (e.g., 'en', 'es') or None for auto-detect
        prompt: Optional context text for better accuracy
        multilingual: Detect language per segment instead of once for the whole
            clip. Lets a single recording that switches languages (e.g. Japanese
            then English) transcribe every part instead of dropping the parts
            that are not the dominant language.

    Returns:
        (text, detected_language)
    """
    from faster_whisper import WhisperModel

    # Initialize model
    model = WhisperModel(
        model_size,
        device=device,
        compute_type="float16" if device == "cuda" else "int8",
    )

    # Transcribe
    segments, info = model.transcribe(
        audio_path,
        language=language,
        initial_prompt=prompt,
        beam_size=5,
        vad_filter=True,  # Voice activity detection to remove silence
        multilingual=multilingual,
    )

    # Combine all segments
    text = " ".join(segment.text for segment in segments)

    # Clean up extra whitespace
    text = " ".join(text.split())

    return text, info.language


def main():
    parser = argparse.ArgumentParser(
        description="Transcribe audio files using faster-whisper"
    )
    parser.add_argument("audio_file", help="Path to audio file to transcribe")
    parser.add_argument(
        "--model",
        default="base",
        choices=["tiny", "base", "small", "medium", "large-v1", "large-v2", "large-v3"],
        help="Whisper model size (default: base)",
    )
    parser.add_argument(
        "--device",
        default="auto",
        choices=["auto", "cpu", "cuda"],
        help="Device to use (default: auto)",
    )
    parser.add_argument(
        "--language",
        help="Language code (e.g., en, es) for faster/more accurate transcription",
    )
    parser.add_argument(
        "--prompt",
        help="Context words for better accuracy",
    )
    parser.add_argument(
        "--lang-file",
        help="Write the detected language code (e.g. en, da, ja) to this file",
    )
    parser.add_argument(
        "--multilingual",
        action="store_true",
        help="Detect language per segment so one recording can mix languages",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug output",
    )

    args = parser.parse_args()

    if args.debug:
        logging.getLogger("faster_whisper").setLevel(logging.DEBUG)

    # Check if audio file exists
    if not Path(args.audio_file).exists():
        print(f"Error: Audio file not found: {args.audio_file}", file=sys.stderr)
        sys.exit(1)

    try:
        result, detected_language = transcribe_file(
            args.audio_file,
            model_size=args.model,
            device=args.device,
            language=args.language,
            prompt=args.prompt,
            multilingual=args.multilingual,
        )
        if args.lang_file:
            Path(args.lang_file).write_text(detected_language or "")
        print(result)
    except Exception as e:
        print(f"Error during transcription: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
