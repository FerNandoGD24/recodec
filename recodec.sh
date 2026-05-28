#!/bin/bash

TOTAL_THREADS=$(nproc)
TARGET_THREADS=$(( TOTAL_THREADS / 2 ))
[ "$TARGET_THREADS" -lt 1 ] && TARGET_THREADS=1
CPU_CORES=$(seq -s, 0 $((TARGET_THREADS - 1)))

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

is_valid_video_ext() {
    local ext="${1##*.}"
    ext="${ext,,}"
    case "$ext" in
        mp4|mkv|mov|avi|mxf|m4v|ts|mts|m2ts|webm|flv|wmv|mpg|mpeg|vob) return 0 ;;
        *) return 1 ;;
    esac
}

run_ffmpeg() {
    nice -n 10 taskset -c "$CPU_CORES" ionice -c 2 -n 7 ffmpeg -hide_banner -loglevel error "$@"
}

run_with_spinner() {
    local desc="$1"; shift
    local spinner=('|' '/' '-' '\\') i=0
    printf "%s... " "$desc"
    run_ffmpeg "$@" &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
        printf "\r%s %s" "$desc" "${spinner[i++ % 4]}"
        sleep 0.25
    done
    wait $pid 2>/dev/null
    local ret=$?
    printf "\r%s %s\n" "$desc" "${spinner[i % 4]}"
    return $ret
}

valid_files=()
if [ $# -gt 0 ]; then
    for arg in "$@"; do
        [ -f "$arg" ] && is_valid_video_ext "$arg" && valid_files+=("$arg")
    done
else
    echo "Buscando videos en el directorio actual..."
    while IFS= read -r -d '' file; do
        valid_files+=("$file")
    done < <(find . -maxdepth 1 -type f \( \
        -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o \
        -iname "*.mxf" -o -iname "*.m4v" -o -iname "*.ts" -o -iname "*.mts" -o \
        -iname "*.m2ts" -o -iname "*.webm" -o -iname "*.flv" -o -iname "*.wmv" -o \
        -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.vob" \) -print0 | sort -z)
fi

[ ${#valid_files[@]} -eq 0 ] && { echo "No se encontraron archivos soportados."; exit 0; }

successful=()
failed=()

for input in "${valid_files[@]}"; do
    dir="$(dirname "$input")"
    base="$(basename "$input")"
    name="${base%.*}"
    out_dir="$dir/${name}_output"
    mkdir -p "$out_dir/original"
    output_file="$out_dir/${name}.mov"

    echo -e "\n${GREEN}Procesando:${NC} $input"

    [ -f "$output_file" ] && { echo "  Ya existe, saltando."; successful+=("$input"); continue; }

    audio_count=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$input" 2>/dev/null | wc -l)
    audio_extracted=()
    for ((i=0; i<audio_count; i++)); do
        audio_out="$out_dir/${name}_audio_track_${i}.wav"
        echo "  Extrayendo pista $i (estéreo) -> $(basename "$audio_out")"
        if run_with_spinner "  Pista $i" -i "$input" -map "0:a:$i" -ac 2 -c:a pcm_s16le -ar 48000 -y "$audio_out"; then
            audio_extracted+=("$audio_out")
        else
            echo -e "${RED}  Error al extraer pista $i${NC}"
        fi
    done

    echo "  Copiando video -> $(basename "$output_file")"
    if run_with_spinner "  Video" -i "$input" -c:v copy -an -f mov -y "$output_file"; then
        mv "$input" "$out_dir/original/" 2>/dev/null || true
        echo -e "${GREEN}  Listo:${NC} ${#audio_extracted[@]} pista(s) de audio y video guardados."
        successful+=("$input")
    else
        echo -e "${RED}  Error al copiar video. Abortando.${NC}"
        rm -f "$output_file" "${audio_extracted[@]}" 2>/dev/null || true
        failed+=("$input")
    fi
done

echo -e "\n${GREEN}=== Resumen ===${NC}"
echo "Exitosos: ${#successful[@]}"
if [ ${#failed[@]} -gt 0 ]; then
    echo -e "${RED}Fallidos: ${#failed[@]}${NC}"
    for f in "${failed[@]}"; do echo "  - $f"; done
fi
