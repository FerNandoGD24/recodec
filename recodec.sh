#!/bin/bash
set -euo pipefail

# --- Config ---
INPUT_DIR="${1:-.}"
OUTPUT_DIR="output"
VIDEO_DIR="$OUTPUT_DIR/video"
AUDIO_DIR="$OUTPUT_DIR/audio"
VIDEO_EXTS="mp4|mkv|avi|m4v|webm|flv|wmv|ts|m2ts|mts|mov"
AUDIO_EXTS="mp3|aac|flac|ogg|wma|m4a|opus|wav"

mkdir -p "$VIDEO_DIR/audio" "$VIDEO_DIR/originals"
mkdir -p "$AUDIO_DIR/originals"

is_video() { echo "${1##*.}" | grep -qiE "^($VIDEO_EXTS)$"; }
is_audio() { echo "${1##*.}" | grep -qiE "^($AUDIO_EXTS)$"; }

# --- Videos ---
for file in "$INPUT_DIR"/*; do
  [[ -f "$file" ]] || continue
  fname=$(basename "$file")
  name="${fname%.*}"
  is_video "$fname" || continue

  echo "Video: $fname"

  # Original
  mv "$file" "$VIDEO_DIR/originals/"
  src="$VIDEO_DIR/originals/$fname"

  # Recode to ProRes 422 HQ
  ffmpeg -y -i "$src" \
    -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le \
    -an \
    "$VIDEO_DIR/${name}.mov" \
    -loglevel warning

  # Extract each audio track to WAV stereo 24-bit
  mapfile -t streams < <(
    ffprobe -v error -select_streams a \
      -show_entries stream=index -of csv=p=0 "$src"
  )

  if [[ ${#streams[@]} -eq 0 ]]; then
    echo "  No audio tracks found"
  else
    t=1
    for idx in "${streams[@]}"; do
      ffmpeg -y -i "$src" \
        -map 0:"$idx" -ac 2 -c:a pcm_s24le \
        "$VIDEO_DIR/audio/${name}_track${t}.wav" \
        -loglevel warning
      echo "  Track $t extracted"
      ((t++))
    done
  fi
done

# --- Audio files ---
for file in "$INPUT_DIR"/*; do
  [[ -f "$file" ]] || continue
  fname=$(basename "$file")
  name="${fname%.*}"
  is_audio "$fname" || continue

  # Skip WAV files already in correct folder
  [[ "$fname" == *.wav ]] && continue

  echo "Audio: $fname"

  mv "$file" "$AUDIO_DIR/originals/"
  ffmpeg -y -i "$AUDIO_DIR/originals/$fname" \
    -ac 2 -c:a pcm_s24le \
    "$AUDIO_DIR/${name}.wav" \
    -loglevel warning
done

echo ""
echo "Done. Output structure:"
echo "  $VIDEO_DIR/"
echo "    ├── *.mov          (ProRes 422 HQ)"
echo "    ├── audio/"
echo "    │   └── *_trackN.wav"
echo "    └── originals/"
echo "  $AUDIO_DIR/"
echo "    ├── *.wav"
echo "    └── originals/"
