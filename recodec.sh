#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOTAL_THREADS=$(nproc)
TARGET_THREADS=$(( TOTAL_THREADS * 7 / 10 ))
if [ "$TARGET_THREADS" -lt 2 ]; then
  TARGET_THREADS=2
elif [ "$TARGET_THREADS" -gt "$TOTAL_THREADS" ]; then
  TARGET_THREADS="$TOTAL_THREADS"
fi
CPU_CORES=$(seq -s, 0 $((TARGET_THREADS - 1)))
NICE_LEVEL=10

set -e

if [ $# -eq 0 ]; then
  echo "Uso: $0 archivo1.{mp4,mkv} [archivo2.{mp4,mkv} ...]"
  exit 1
fi

show_percent() {
  local INPUT_FILE="$1"
  local DURATION_SEC
  DURATION_SEC=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT_FILE" 2>/dev/null)
  if [[ -z "$DURATION_SEC" || "$DURATION_SEC" == "N/A" ]]; then
    cat >/dev/null
    return
  fi

  DURATION_SEC=$(printf "%.0f" "$DURATION_SEC" 2>/dev/null)
  if ! [[ "$DURATION_SEC" =~ ^[0-9]+$ ]] || [ "$DURATION_SEC" -le 0 ]; then
    cat >/dev/null
    return
  fi

  awk -v dur="$DURATION_SEC" '
    /^out_time_us=/ {
      gsub(/[^0-9]/, "", $0);
      time_us = $0;
      if (time_us == "") next;
      time_sec = time_us / 1000000;
      if (time_sec < 0) time_sec = 0;
      if (time_sec > dur) time_sec = dur;
      pct = (time_sec / dur) * 100;
      if (pct > 100) pct = 100;
      printf "\rProgreso: %3.0f%%", pct;
      fflush();
    }
    END { printf "\n" }
  '
}

run_ffmpeg_limited() {
  nice -n "$NICE_LEVEL" taskset -c "$CPU_CORES" ionice -c 2 -n 7 ffmpeg "$@"
}

get_audio_track_count() {
  ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$1" 2>/dev/null | wc -l
}

process_file() {
  local INPUT="$1"
  local EXT="${INPUT##*.}"
  EXT="${EXT,,}"

  if [[ "$EXT" != "mp4" && "$EXT" != "mkv" ]]; then
    return 1
  fi

  local DIR BASENAME OUTPUT ARCHIVE_DIR
  DIR="$(dirname "$INPUT")"
  BASENAME="$(basename "$INPUT" .${EXT})"
  OUTPUT="$DIR/${BASENAME}.mov"
  ARCHIVE_DIR="$DIR/input"

  if [ -f "$OUTPUT" ]; then
    return 0
  fi

  local audio_tracks
  audio_tracks=$(get_audio_track_count "$INPUT") 2>/dev/null || audio_tracks=0

  echo "Procesando: $INPUT (pistas de audio: $audio_tracks, hilos: $CPU_CORES)"
  echo "  Salida de video: $OUTPUT"
  mkdir -p "$ARCHIVE_DIR"

  # 1. Extraer pistas de audio como .wav estéreo
  local extracted_audio=()
  local failed_audio=0
  for ((i=0; i<audio_tracks; i++)); do
    local audio_output="$DIR/${BASENAME}_audio_track_${i}.wav"
    echo "  Extrayendo pista de audio $i → $audio_output"
    if ! run_ffmpeg_limited \
        -hide_banner -loglevel error -i "$INPUT" \
        -map "0:a:$i" \
        -c:a pcm_s16le -ac 2 -ar 48000 \
        -y "$audio_output" &>/dev/null; then
      echo "    Error al extraer pista de audio $i"
      ((failed_audio++))
    else
      extracted_audio+=("$audio_output")
    fi
  done

  if [ "$failed_audio" -eq "$audio_tracks" ] && [ "$audio_tracks" -gt 0 ]; then
    echo "  Todas las pistas de audio fallaron. Abortando."
    return 1
  fi

  # 2. Codificar video SIN audio
  echo -n "  Codificando video sin audio... "
  if run_ffmpeg_limited \
      -hide_banner -loglevel error -i "$INPUT" \
      -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p \
      -an -f mov -y "$OUTPUT" &>/dev/null; then
    echo "OK"
  else
    echo "Error"
    # Limpiar archivos de audio si el video falla
    for f in "${extracted_audio[@]}"; do
      rm -f "$f"
    done
    return 1
  fi

  # Mover original
  mv "$INPUT" "$ARCHIVE_DIR/" 2>/dev/null || true
  echo "Listo: $OUTPUT y ${#extracted_audio[@]} pistas de audio .wav"
  return 0
}

declare -A elapsed_times
successful_files=()
failed_files=()

for INPUT in "$@"; do
  if [ ! -f "$INPUT" ]; then
    echo -e "${YELLOW}Advertencia: archivo no encontrado, saltando: $INPUT${NC}"
    failed_files+=("$INPUT (no encontrado)")
    continue
  fi

  EXT="${INPUT##*.}"
  if [[ "${EXT,,}" != "mp4" && "${EXT,,}" != "mkv" ]]; then
    echo -e "${YELLOW}Advertencia: formato no soportado, saltando: $INPUT${NC}"
    failed_files+=("$INPUT (formato no soportado)")
    continue
  fi

  START=$(date +%s)
  if process_file "$INPUT"; then
    END=$(date +%s)
    elapsed_times["$INPUT"]=$((END - START))
    successful_files+=("$INPUT")
  else
    failed_files+=("$INPUT")
  fi
  echo
done

retry_failed=()
for f in "${failed_files[@]}"; do
  if [[ "$f" == *" (no encontrado)" ]] || [[ "$f" == *" (formato no soportado)" ]]; then
    retry_failed+=("$f")
    continue
  fi

  INPUT="$f"
  DIR="$(dirname "$INPUT")"
  BASENAME="$(basename "$INPUT")"
  BASENAME="${BASENAME%.*}"
  OUTPUT="$DIR/${BASENAME}.mov"

  # Limpiar salidas parciales
  if [ -f "$OUTPUT" ]; then
    rm -f "$OUTPUT"
    echo "Eliminado archivo parcial: $OUTPUT"
  fi
  # También borrar posibles .wav parciales
  for wav in "$DIR/${BASENAME}_audio_track_"*.wav; do
    [ -f "$wav" ] && rm -f "$wav"
  done

  echo "Reintentando: $INPUT"
  START=$(date +%s)
  if process_file "$INPUT"; then
    END=$(date +%s)
    elapsed_times["$INPUT"]=$((END - START))
    successful_files+=("$INPUT")
  else
    retry_failed+=("$INPUT")
  fi
  echo
done
failed_files=("${retry_failed[@]}")

corrupted_originals=()
temp_success=()

for orig in "${successful_files[@]}"; do
  if [[ "$orig" == *" (no encontrado)" ]] || [[ "$orig" == *" (formato no soportado)" ]]; then
    temp_success+=("$orig")
    continue
  fi

  EXT="${orig##*.}"
  DIR="$(dirname "$orig")"
  BASENAME="$(basename "$orig" .${EXT,,})"
  mov="$DIR/${BASENAME}.mov"

  if [ -f "$mov" ]; then
    echo -n "Verificando: $(basename "$mov") ... "
    if ffmpeg -v error -i "$mov" -f null -nostdin - &>/dev/null; then
      echo "OK"
      temp_success+=("$orig")
    else
      echo "CORRUPTO"
      rm -f "$mov"
      # Borrar .wav asociados
      for wav in "$DIR/${BASENAME}_audio_track_"*.wav; do
        [ -f "$wav" ] && rm -f "$wav"
      done
      failed_files+=("$orig (corrupto tras conversión)")
    fi
  else
    failed_files+=("$orig (salida .mov no encontrada)")
  fi
done
successful_files=("${temp_success[@]}")

echo
echo "==========================================="
echo "RESUMEN FINAL"
echo "==========================================="

if [ ${#successful_files[@]} -gt 0 ]; then
  echo -e "${GREEN}Archivos procesados correctamente (${#successful_files[@]}):${NC}"
  for f in "${successful_files[@]}"; do
    if [[ -v elapsed_times["$f"] ]]; then
      echo -e "  $f (${elapsed_times["$f"]}s)"
    else
      echo "  $f"
    fi
  done
else
  echo "Ningún archivo se procesó correctamente."
fi

echo

if [ ${#failed_files[@]} -gt 0 ]; then
  echo -e "${RED}Archivos con errores (${#failed_files[@]}):${NC}"
  for f in "${failed_files[@]}"; do
    echo "  $f"
  done
else
  echo "No hubo errores."
fi

echo
echo "Los archivos originales procesados se guardaron en la carpeta 'input/'."
echo "Los archivos de audio se guardaron como 'nombre_audio_track_N.wav'."
echo "Conversión completada."
