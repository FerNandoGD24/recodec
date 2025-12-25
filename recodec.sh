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

valid_files=()
for arg in "$@"; do
  if [ -f "$arg" ]; then
    ext="${arg##*.}"
    if [[ "${ext,,}" == "mp4" || "${ext,,}" == "mkv" ]]; then
      valid_files+=("$arg")
    fi
  fi
done

if [ ${#valid_files[@]} -eq 0 ]; then
  exit 0
fi

VIDEO_MODE=2
AUDIO_MODE=3
FPS_MODE=2

while true; do
  clear
  echo "============================="
  echo "     Menú de Recodec"
  echo "============================="
  echo
  case $VIDEO_MODE in
    1) echo "Codec de video : Mantener el codec original" ;;
    2) echo "Codec de video : Cambiar a DNxHR-SQ" ;;
  esac
  case $AUDIO_MODE in
    1) echo "Modo de audio  : Separar en 2 pistas mono por canal" ;;
    2) echo "Modo de audio  : Separar en pista mono por cada canal" ;;
    3) echo "Modo de audio  : Separar por canales stereo" ;;
    4) echo "Modo de audio  : Comprimir a 1 archivo mono" ;;
    5) echo "Modo de audio  : Comprimir a 1 archivo stereo" ;;
  esac
  case $FPS_MODE in
    1) echo "Fotogramas     : 60 fps" ;;
    2) echo "Fotogramas     : 30 fps" ;;
  esac
  echo
  echo "1) Cambiar codec de video"
  echo "2) Cambiar modo de audio"
  echo "3) Cambiar fotogramas por segundo"
  echo "4) Iniciar procesamiento"
  echo
  read -p "Selecciona una opción [1-4]: " opt
  case $opt in
    1)
      echo
      echo "1) Mantener el codec original (Menor tiempo de procesamiento al ejecutar el script, sin recodificación; menor fluidez al editar)"
      echo "2) Cambiar a DNxHR-SQ (mejor fluidez al editar, más espacio en disco y tiempo al ejecutar el script; mayor fluidez al editar)"
      read -p "Elige una opción [1-2]: " m
      if [[ "$m" == "1" || "$m" == "2" ]]; then VIDEO_MODE=$m; fi
      ;;
    2)
      echo
      echo "1) Separar en 2 pistas mono por canal (ej. 4 canales = 8 archivos)"
      echo "2) Separar en pista mono por cada canal (ej. 4 pistas stereo = 4 archivos mono)"
      echo "3) Separar por canales stereo (ej. 4 pistas = 4 archivos stereo)"
      echo "4) Comprimir a 1 archivo mono (todas las pistas → 1 mono)"
      echo "5) Comprimir a 1 archivo stereo (todas las pistas → 1 stereo)"
      read -p "Elige una opción [1-5]: " m
      if [[ "$m" =~ ^[1-5]$ ]]; then AUDIO_MODE=$m; fi
      ;;
    3)
      echo
      echo "Fotogramas por segundo (fps) del video de salida:"
      echo "1) 60 fps"
      echo "2) 30 fps"
      read -p "Elige una opción [1-2]: " m
      if [[ "$m" == "1" || "$m" == "2" ]]; then FPS_MODE=$m; fi
      ;;
    4) break ;;
    *) sleep 0 ;;
  esac
done

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
  local extracted_audio=()
  local failed_audio=0
  if [ "$audio_tracks" -gt 0 ]; then
    if [ "$AUDIO_MODE" -eq 4 ] || [ "$AUDIO_MODE" -eq 5 ]; then
      local ac=2; [ "$AUDIO_MODE" -eq 4 ] && ac=1
      local suffix="$([ "$ac" -eq 1 ] && echo "mono" || echo "stereo")"
      local audio_output="$DIR/${BASENAME}_audio_all_${suffix}.wav"
      echo "  Mezclando todas las pistas en 1 archivo $suffix → $audio_output"
      if ! run_ffmpeg_limited -hide_banner -loglevel error -i "$INPUT" -map 0:a -ac $ac -c:a pcm_s16le -ar 48000 -y "$audio_output" &>/dev/null; then
        echo "    Error al mezclar todas las pistas"
        return 1
      else
        extracted_audio+=("$audio_output")
      fi
    else
      for ((i=0; i<audio_tracks; i++)); do
        case $AUDIO_MODE in
          1)
            for ch in 0 1; do
              local audio_output="$DIR/${BASENAME}_audio_track_${i}_ch${ch}.wav"
              echo "  Extrayendo pista $i, canal $ch → $audio_output"
              if ! run_ffmpeg_limited -hide_banner -loglevel error -i "$INPUT" -map "0:a:$i" -filter:a "pan=mono|c0=c$ch" -c:a pcm_s16le -ar 48000 -y "$audio_output" &>/dev/null; then
                ((failed_audio++))
              else
                extracted_audio+=("$audio_output")
              fi
            done
            ;;
          2)
            local audio_output="$DIR/${BASENAME}_audio_track_${i}_mono.wav"
            echo "  Mezclando pista $i a mono → $audio_output"
            if ! run_ffmpeg_limited -hide_banner -loglevel error -i "$INPUT" -map "0:a:$i" -ac 1 -c:a pcm_s16le -ar 48000 -y "$audio_output" &>/dev/null; then
              ((failed_audio++))
            else
              extracted_audio+=("$audio_output")
            fi
            ;;
          3)
            local audio_output="$DIR/${BASENAME}_audio_track_${i}.wav"
            echo "  Extrayendo pista $i como stereo → $audio_output"
            if ! run_ffmpeg_limited -hide_banner -loglevel error -i "$INPUT" -map "0:a:$i" -c:a pcm_s16le -ac 2 -ar 48000 -y "$audio_output" &>/dev/null; then
              ((failed_audio++))
            else
              extracted_audio+=("$audio_output")
            fi
            ;;
        esac
      done
      if [ "$failed_audio" -eq "$audio_tracks" ]; then
        echo "  Todas las pistas de audio fallaron. Abortando."
        return 1
      fi
    fi
  fi
  local fps_opt=""
  if [ "$FPS_MODE" -eq 1 ]; then
    fps_opt="-r 60"
  elif [ "$FPS_MODE" -eq 2 ]; then
    fps_opt="-r 30"
  fi
  echo -n "  Codificando video sin audio... "
  if [ "$VIDEO_MODE" -eq 1 ]; then
    if run_ffmpeg_limited -hide_banner -loglevel error -i "$INPUT" -c:v copy $fps_opt -an -f mov -y "$OUTPUT" &>/dev/null; then
      echo "OK (copiado)"
    else
      echo "Error"
      for f in "${extracted_audio[@]}"; do rm -f "$f"; done
      return 1
    fi
  else
    if run_ffmpeg_limited -hide_banner -loglevel error -i "$INPUT" $fps_opt -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p -an -f mov -y "$OUTPUT" &>/dev/null; then
      echo "OK"
    else
      echo "Error"
      for f in "${extracted_audio[@]}"; do rm -f "$f"; done
      return 1
    fi
  fi
  mv "$INPUT" "$ARCHIVE_DIR/" 2>/dev/null || true
  echo "Listo: $OUTPUT y ${#extracted_audio[@]} pistas de audio .wav"
  return 0
}

declare -A elapsed_times
successful_files=()
failed_files=()

for INPUT in "${valid_files[@]}"; do
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
  if [ -f "$OUTPUT" ]; then
    rm -f "$OUTPUT"
    echo "Eliminado archivo parcial: $OUTPUT"
  fi
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
if [ "$VIDEO_MODE" -eq 2 ]; then
  echo "Video convertido a DNxHR-SQ."
else
  echo "Video copiado sin cambios de codec."
fi
echo "Archivos de audio generados según modo seleccionado."
echo "Conversión completada."
