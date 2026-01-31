#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuración de núcleos
TOTAL_THREADS=$(nproc)
DEFAULT_TARGET_THREADS=$(( TOTAL_THREADS * 7 / 10 ))
if [ "$DEFAULT_TARGET_THREADS" -lt 2 ]; then
    DEFAULT_TARGET_THREADS=2
elif [ "$DEFAULT_TARGET_THREADS" -gt "$TOTAL_THREADS" ]; then
    DEFAULT_TARGET_THREADS="$TOTAL_THREADS"
fi
TARGET_THREADS="$DEFAULT_TARGET_THREADS"

update_cpu_cores() {
    CPU_CORES=$(seq -s, 0 $((TARGET_THREADS - 1)))
}
update_cpu_cores

NICE_LEVEL=10
set -e

# === Función para detectar extensiones válidas ===
is_valid_video_ext() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"  # minúsculas

    case "$ext" in
        mp4|mkv|mov|avi|mxf|m4v|ts|mts|m2ts|webm|flv|wmv|mpg|mpeg|vob)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# === Progreso aproximado (spinner) ===
show_approximate_progress() {
    local message="$1"
    local pid_file="$2"
    local i=0
    local spinner=('|' '/' '-' '\\')
    printf "%s... " "$message"
    while [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; do
        printf "\b${spinner[i++ % 4]}"
        sleep 0.25
    done
    printf "\b \n"
}

# === CORREGIDO: Detectar pistas de audio vacías ===
is_audio_track_silent() {
    local input_file="$1"
    local track_index="$2"
    local duration_sec
    local rms_line
    local rms_value

    duration_sec=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$input_file" 2>/dev/null)
    if [[ -z "$duration_sec" || "$duration_sec" == "N/A" ]]; then
        duration_sec=30
    else
        duration_sec=$(awk 'BEGIN{print ('$duration_sec' > 30) ? 30 : '$duration_sec'}')
    fi

    rms_line=$(ffmpeg -nostdin -hide_banner -i "$input_file" \
        -map "0:a:$track_index" \
        -t "$duration_sec" \
        -af "astats=metadata=1:reset=1,ametadata=mode=print:key=lavfi.astats.1.RMS_level:file=-" \
        -f null - 2>/dev/null | tail -n1)

    if [[ -z "$rms_line" ]]; then
        return 1  # asumimos que hay audio
    fi

    # Extraer solo el valor numérico o "-inf"
    rms_value=$(echo "$rms_line" | sed -n 's/.*=\([0-9.-]*\)/\1/p')

    if [[ -z "$rms_value" ]]; then
        if [[ "$rms_line" == *"-inf"* ]]; then
            return 0  # silencio total
        else
            return 1
        fi
    fi

    if [[ "$rms_value" == "-inf" ]]; then
        return 0
    fi

    # Comparar valor numérico
    if awk "BEGIN {exit ($rms_value < -55) ? 0 : 1}"; then
        return 0
    else
        return 1
    fi
}

# Detección de archivos
valid_files=()

if [ $# -gt 0 ]; then
    for arg in "$@"; do
        if [ -f "$arg" ] && is_valid_video_ext "$arg"; then
            valid_files+=("$arg")
        fi
    done
else
    echo "No se especificaron archivos. Buscando videos soportados en el directorio actual..."
    while IFS= read -r -d '' file; do
        valid_files+=("$file")
    done < <(find . -maxdepth 1 -type f \( \
        -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o \
        -iname "*.mxf" -o -iname "*.m4v" -o -iname "*.ts" -o -iname "*.mts" -o \
        -iname "*.m2ts" -o -iname "*.webm" -o -iname "*.flv" -o -iname "*.wmv" -o \
        -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.vob" \
    \) -print0 | sort -z)
fi

if [ ${#valid_files[@]} -eq 0 ]; then
    echo "No se encontraron archivos de video soportados para procesar."
    exit 0
fi

# Modos predeterminados
VIDEO_MODE=2
AUDIO_MODE=3
FPS_MODE=2

# Progreso para codificación (con -progress)
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

# Ejecución de ffmpeg
run_ffmpeg_limited() {
    nice -n "$NICE_LEVEL" taskset -c "$CPU_CORES" ionice -c 2 -n 7 ffmpeg -hide_banner -loglevel error "$@"
}

run_ffmpeg_with_progress() {
    local input="$1"; shift
    {
        run_ffmpeg_limited -progress pipe:1 -nostdin "$@" 2>/dev/null
    } | show_percent "$input"
}

# === CORREGIDO: Ejecutar ffmpeg con spinner sin exec ===
run_ffmpeg_with_spinner() {
    local desc="$1"; shift
    local tmp_pid="/tmp/ffmpeg_$$"
    (
        echo $BASHPID > "$tmp_pid"
        run_ffmpeg_limited "$@"
    ) &
    show_approximate_progress "$desc" "$tmp_pid"
    wait $!
    local ret=$?
    rm -f "$tmp_pid"
    return $ret
}

# Funciones auxiliares
get_audio_track_count() {
    ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$1" 2>/dev/null | wc -l
}

# Exportación
export_file() {
    local INPUT="$1"
    local MODE="$2"
    if ! is_valid_video_ext "$INPUT"; then
        return 1
    fi

    local DIR BASENAME EXT OUTPUT_DIR ARCHIVE_SUBDIR
    DIR="$(dirname "$INPUT")"
    BASENAME=$(basename "$INPUT")
    EXT="${BASENAME##*.}"
    BASENAME="${BASENAME%.*}"
    OUTPUT_DIR="$DIR/${BASENAME}_output"
    mkdir -p "$OUTPUT_DIR"
    ARCHIVE_SUBDIR="$OUTPUT_DIR/original"
    mkdir -p "$ARCHIVE_SUBDIR"

    echo "Exportando: $INPUT"

    if [[ "$MODE" == "1" || "$MODE" == "3" ]]; then
        local VIDEO_OUTPUT="$OUTPUT_DIR/${BASENAME}_video_only.mov"
        echo "  -> Video: $VIDEO_OUTPUT"
        if ! run_ffmpeg_with_spinner "Extrayendo video" -i "$INPUT" -c:v copy -an -f mov -y "$VIDEO_OUTPUT"; then
            echo "    Error al extraer video"
        fi
    fi

    if [[ "$MODE" == "2" || "$MODE" == "3" ]]; then
        local audio_tracks
        audio_tracks=$(get_audio_track_count "$INPUT") 2>/dev/null || audio_tracks=0
        if [ "$audio_tracks" -gt 0 ]; then
            if [ "$AUDIO_MODE" -eq 4 ] || [ "$AUDIO_MODE" -eq 5 ]; then
                local ac=2; [ "$AUDIO_MODE" -eq 4 ] && ac=1
                local suffix="$([ "$ac" -eq 1 ] && echo "mono" || echo "stereo")"
                local audio_output="$OUTPUT_DIR/${BASENAME}_audio_all_${suffix}.wav"
                echo "  -> Audio mezclado ($suffix): $audio_output"

                non_silent_tracks=()
                for ((i=0; i<audio_tracks; i++)); do
                    if ! is_audio_track_silent "$INPUT" "$i"; then
                        non_silent_tracks+=("$i")
                    fi
                done

                if [ ${#non_silent_tracks[@]} -eq 0 ]; then
                    echo "    -> Todas las pistas están vacías. Saltando."
                else
                    map_args=()
                    for idx in "${non_silent_tracks[@]}"; do
                        map_args+=("-map" "0:a:$idx")
                    done
                    if [ ${#non_silent_tracks[@]} -eq 1 ]; then
                        if ! run_ffmpeg_with_spinner "Mezclando audio" -i "$INPUT" "${map_args[@]}" -ac $ac -c:a pcm_s16le -ar 48000 -y "$audio_output"; then
                            echo "    Error al mezclar audio"
                        fi
                    else
                        if ! run_ffmpeg_with_spinner "Mezclando audio" -i "$INPUT" "${map_args[@]}" -filter_complex "amix=inputs=${#non_silent_tracks[@]}:duration=longest:normalize=0" -ac $ac -c:a pcm_s16le -ar 48000 -y "$audio_output"; then
                            echo "    Error al mezclar audio"
                        fi
                    fi
                fi
            else
                for ((i=0; i<audio_tracks; i++)); do
                    if is_audio_track_silent "$INPUT" "$i"; then
                        echo "  -> Pista $i está vacía. Saltando."
                        continue
                    fi

                    case $AUDIO_MODE in
                        1)
                            for ch in 0 1; do
                                local audio_output="$OUTPUT_DIR/${BASENAME}_audio_track_${i}_ch${ch}.wav"
                                echo "  -> Audio pista $i, canal $ch -> $audio_output"
                                run_ffmpeg_with_spinner "Pista $i, canal $ch" -i "$INPUT" -map "0:a:$i" -filter:a "pan=mono|c0=c$ch" -c:a pcm_s16le -ar 48000 -y "$audio_output" || true
                            done
                            ;;
                        2)
                            local audio_output="$OUTPUT_DIR/${BASENAME}_audio_track_${i}_mono.wav"
                            echo "  -> Audio pista $i (mono) -> $audio_output"
                            run_ffmpeg_with_spinner "Pista $i mono" -i "$INPUT" -map "0:a:$i" -ac 1 -c:a pcm_s16le -ar 48000 -y "$audio_output" || true
                            ;;
                        3)
                            local audio_output="$OUTPUT_DIR/${BASENAME}_audio_track_${i}.wav"
                            echo "  -> Audio pista $i (stereo) -> $audio_output"
                            run_ffmpeg_with_spinner "Pista $i stereo" -i "$INPUT" -map "0:a:$i" -c:a pcm_s16le -ac 2 -ar 48000 -y "$audio_output" || true
                            ;;
                    esac
                done
            fi
        else
            echo "  -> No hay pistas de audio."
        fi
    fi

    if [ -f "$OUTPUT_DIR/${BASENAME}_video_only.mov" ] || compgen -G "$OUTPUT_DIR/${BASENAME}_audio_*.wav" > /dev/null; then
        mv "$INPUT" "$ARCHIVE_SUBDIR/" 2>/dev/null || true
    fi
}

# Procesamiento principal
process_file() {
    local INPUT="$1"
    if ! is_valid_video_ext "$INPUT"; then
        return 1
    fi

    local DIR BASENAME EXT OUTPUT_DIR OUTPUT ARCHIVE_SUBDIR
    DIR="$(dirname "$INPUT")"
    BASENAME=$(basename "$INPUT")
    EXT="${BASENAME##*.}"
    BASENAME="${BASENAME%.*}"
    OUTPUT_DIR="$DIR/${BASENAME}_output"
    mkdir -p "$OUTPUT_DIR"
    OUTPUT="$OUTPUT_DIR/${BASENAME}.mov"
    ARCHIVE_SUBDIR="$OUTPUT_DIR/original"
    mkdir -p "$ARCHIVE_SUBDIR"
    if [ -f "$OUTPUT" ]; then
        return 0
    fi

    local audio_tracks
    audio_tracks=$(get_audio_track_count "$INPUT") 2>/dev/null || audio_tracks=0
    echo "Procesando: $INPUT (pistas de audio: $audio_tracks, hilos: $CPU_CORES)"
    echo "  Salida de video: $OUTPUT"
    local extracted_audio=()
    local failed_audio=0

    if [ "$audio_tracks" -gt 0 ]; then
        if [ "$AUDIO_MODE" -eq 4 ] || [ "$AUDIO_MODE" -eq 5 ]; then
            local ac=2; [ "$AUDIO_MODE" -eq 4 ] && ac=1
            local suffix="$([ "$ac" -eq 1 ] && echo "mono" || echo "stereo")"
            local audio_output="$OUTPUT_DIR/${BASENAME}_audio_all_${suffix}.wav"
            echo "  Mezclando todas las pistas en 1 archivo $suffix -> $audio_output"

            non_silent_tracks=()
            for ((i=0; i<audio_tracks; i++)); do
                if ! is_audio_track_silent "$INPUT" "$i"; then
                    non_silent_tracks+=("$i")
                fi
            done

            if [ ${#non_silent_tracks[@]} -eq 0 ]; then
                echo "    -> Todas las pistas están vacías."
            else
                map_args=()
                for idx in "${non_silent_tracks[@]}"; do
                    map_args+=("-map" "0:a:$idx")
                done
                if [ ${#non_silent_tracks[@]} -eq 1 ]; then
                    if ! run_ffmpeg_with_spinner "Mezclando audio" -i "$INPUT" "${map_args[@]}" -ac $ac -c:a pcm_s16le -ar 48000 -y "$audio_output"; then
                        echo "    Error al mezclar todas las pistas"
                        return 1
                    else
                        extracted_audio+=("$audio_output")
                    fi
                else
                    if ! run_ffmpeg_with_spinner "Mezclando audio" -i "$INPUT" "${map_args[@]}" -filter_complex "amix=inputs=${#non_silent_tracks[@]}:duration=longest:normalize=0" -ac $ac -c:a pcm_s16le -ar 48000 -y "$audio_output"; then
                        echo "    Error al mezclar todas las pistas"
                        return 1
                    else
                        extracted_audio+=("$audio_output")
                    fi
                fi
            fi
        else
            for ((i=0; i<audio_tracks; i++)); do
                if is_audio_track_silent "$INPUT" "$i"; then
                    echo "  -> Pista $i está vacía. Saltando."
                    continue
                fi

                case $AUDIO_MODE in
                    1)
                        for ch in 0 1; do
                            local audio_output="$OUTPUT_DIR/${BASENAME}_audio_track_${i}_ch${ch}.wav"
                            echo "  Extrayendo pista $i, canal $ch -> $audio_output"
                            if ! run_ffmpeg_with_spinner "Pista $i, canal $ch" -i "$INPUT" -map "0:a:$i" -filter:a "pan=mono|c0=c$ch" -c:a pcm_s16le -ar 48000 -y "$audio_output"; then
                                ((failed_audio++))
                            else
                                extracted_audio+=("$audio_output")
                            fi
                        done
                        ;;
                    2)
                        local audio_output="$OUTPUT_DIR/${BASENAME}_audio_track_${i}_mono.wav"
                        echo "  Mezclando pista $i a mono -> $audio_output"
                        if ! run_ffmpeg_with_spinner "Pista $i mono" -i "$INPUT" -map "0:a:$i" -ac 1 -c:a pcm_s16le -ar 48000 -y "$audio_output"; then
                            ((failed_audio++))
                        else
                            extracted_audio+=("$audio_output")
                        fi
                        ;;
                    3)
                        local audio_output="$OUTPUT_DIR/${BASENAME}_audio_track_${i}.wav"
                        echo "  Extrayendo pista $i como stereo -> $audio_output"
                        if ! run_ffmpeg_with_spinner "Pista $i stereo" -i "$INPUT" -map "0:a:$i" -c:a pcm_s16le -ac 2 -ar 48000 -y "$audio_output"; then
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
        if run_ffmpeg_with_spinner "Copiando video" -i "$INPUT" -c:v copy $fps_opt -an -f mov -y "$OUTPUT"; then
            echo "OK (copiado)"
        else
            echo "Error"
            for f in "${extracted_audio[@]}"; do rm -f "$f"; done
            return 1
        fi
    else
        if run_ffmpeg_with_progress "$INPUT" -i "$INPUT" $fps_opt -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p -an -f mov -y "$OUTPUT"; then
            echo "OK"
        else
            echo "Error"
            for f in "${extracted_audio[@]}"; do rm -f "$f"; done
            return 1
        fi
    fi

    mv "$INPUT" "$ARCHIVE_SUBDIR/" 2>/dev/null || true
    echo "Listo: $OUTPUT y ${#extracted_audio[@]} pistas de audio .wav en $OUTPUT_DIR"
    return 0
}

# Menú interactivo
while true; do
    clear
    echo "============================="
    echo "     Menu de Recodec"
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
    echo "Nucleos usados : $TARGET_THREADS (de $TOTAL_THREADS disponibles)"
    echo
    echo "1) Cambiar codec de video"
    echo "2) Cambiar modo de audio"
    echo "3) Cambiar fotogramas por segundo"
    echo "4) Configurar numero de nucleos"
    echo "5) Iniciar procesamiento"
    echo "6) Exportar (solo video, solo audio o todo)"
    echo "7) Salir"
    echo
    read -p "Selecciona una opcion [1-7]: " opt
    case $opt in
        1)
            echo
            echo "1) Mantener el codec original (Menor tiempo de procesamiento al ejecutar el script, sin recodificacion; menor fluidez al editar)"
            echo "2) Cambiar a DNxHR-SQ (mejor fluidez al editar, mas espacio en disco y tiempo al ejecutar el script; mayor fluidez al editar)"
            read -p "Elige una opcion [1-2]: " m
            if [[ "$m" == "1" || "$m" == "2" ]]; then VIDEO_MODE=$m; fi
            ;;
        2)
            echo
            echo "1) Separar en 2 pistas mono por canal (ej. 4 canales = 8 archivos)"
            echo "2) Separar en pista mono por cada canal (ej. 4 pistas stereo = 4 archivos mono)"
            echo "3) Separar por canales stereo (ej. 4 pistas = 4 archivos stereo)"
            echo "4) Comprimir a 1 archivo mono (todas las pistas -> 1 mono)"
            echo "5) Comprimir a 1 archivo stereo (todas las pistas -> 1 stereo)"
            read -p "Elige una opcion [1-5]: " m
            if [[ "$m" =~ ^[1-5]$ ]]; then AUDIO_MODE=$m; fi
            ;;
        3)
            echo
            echo "Fotogramas por segundo (fps) del video de salida:"
            echo "1) 60 fps"
            echo "2) 30 fps"
            read -p "Elige una opcion [1-2]: " m
            if [[ "$m" == "1" || "$m" == "2" ]]; then FPS_MODE=$m; fi
            ;;
        4)
            echo
            echo "Numero actual de nucleos: $TARGET_THREADS"
            echo "Nucleos totales disponibles: $TOTAL_THREADS"
            echo "Valor recomendado (70%): $DEFAULT_TARGET_THREADS"
            read -p "Ingresa numero de nucleos a usar [2-$TOTAL_THREADS] (Enter para mantener $TARGET_THREADS): " user_cores
            if [[ -n "$user_cores" ]]; then
                if [[ "$user_cores" =~ ^[0-9]+$ ]] && [ "$user_cores" -ge 2 ] && [ "$user_cores" -le "$TOTAL_THREADS" ]; then
                    TARGET_THREADS="$user_cores"
                    update_cpu_cores
                else
                    echo "Valor invalido. Se mantiene $TARGET_THREADS."
                    sleep 2
                fi
            fi
            ;;
        5) break ;;
        6)
            echo
            echo "Modo de exportacion:"
            echo "1) Extraer solo video"
            echo "2) Extraer solo audio"
            echo "3) Extraer todo (video + audio)"
            read -p "Elige una opcion [1-3]: " export_opt
            if [[ "$export_opt" =~ ^[1-3]$ ]]; then
                clear
                echo "Iniciando exportacion en modo: $(
                    case $export_opt in
                        1) echo "solo video" ;;
                        2) echo "solo audio" ;;
                        3) echo "todo" ;;
                    esac
                )..."
                sleep 1
                for INPUT in "${valid_files[@]}"; do
                    export_file "$INPUT" "$export_opt"
                    echo
                done
                echo "Exportacion completada."
                read -p "Presiona Enter para regresar al menu..."
            fi
            ;;
        7) exit 0 ;;
        *) sleep 0 ;;
    esac
done

# Procesamiento y registro
declare -A elapsed_times
successful_files=()
failed_files=()
for INPUT in "${valid_files[@]}"; do
    if [ ! -f "$INPUT" ]; then
        echo -e "${YELLOW}Advertencia: archivo no encontrado, saltando: $INPUT${NC}"
        failed_files+=("$INPUT (no encontrado)")
        continue
    fi
    if ! is_valid_video_ext "$INPUT"; then
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

# Reintento
retry_failed=()
for f in "${failed_files[@]}"; do
    if [[ "$f" == *" (no encontrado)" ]] || [[ "$f" == *" (formato no soportado)" ]]; then
        retry_failed+=("$f")
        continue
    fi
    INPUT="$f"
    DIR="$(dirname "$INPUT")"
    BASENAME=$(basename "$INPUT")
    EXT="${BASENAME##*.}"
    BASENAME="${BASENAME%.*}"
    OUTPUT="$DIR/${BASENAME}_output/${BASENAME}.mov"
    if [ -f "$OUTPUT" ]; then
        rm -f "$OUTPUT"
        echo "Eliminado archivo parcial: $OUTPUT"
    fi
    for wav in "$DIR/${BASENAME}_output/${BASENAME}_audio_track_"*.wav; do
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

# Verificación
temp_success=()
for orig in "${successful_files[@]}"; do
    if [[ "$orig" == *" (no encontrado)" ]] || [[ "$orig" == *" (formato no soportado)" ]]; then
        temp_success+=("$orig")
        continue
    fi
    DIR="$(dirname "$orig")"
    BASENAME=$(basename "$orig")
    EXT="${BASENAME##*.}"
    BASENAME="${BASENAME%.*}"
    mov="$DIR/${BASENAME}_output/${BASENAME}.mov"
    if [ -f "$mov" ]; then
        echo -n "Verificando: $(basename "$mov") ... "
        if ffmpeg -v error -i "$mov" -f null -nostdin - &>/dev/null; then
            echo "OK"
            temp_success+=("$orig")
        else
            echo "CORRUPTO"
            rm -f "$mov"
            for wav in "$DIR/${BASENAME}_output/${BASENAME}_audio_track_"*.wav; do
                [ -f "$wav" ] && rm -f "$wav"
            done
            failed_files+=("$orig (corrupto tras conversion)")
        fi
    else
        failed_files+=("$orig (salida .mov no encontrada)")
    fi
done
successful_files=("${temp_success[@]}")

# Resumen final
echo
echo "==========================================="
echo "RESUMEN FINAL"
echo "==========================================="
if [ ${#successful_files[@]} -gt 0 ]; then
    echo -e "${GREEN}Archivos procesados correctamente (${#successful_files[@]}):${NC}"
    for f in "${successful_files[@]}"; do
        if [[ -v elapsed_times["$f"] ]]; then
            echo -e "  $f (${elapsed_times["$f"]}s) -> Carpeta: $(dirname "$f")/$(basename "$f" .${f##*.})_output/"
        else
            echo "  $f -> Carpeta: $(dirname "$f")/$(basename "$f" .${f##*.})_output/"
        fi
    done
else
    echo "Ningun archivo se proceso correctamente."
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
echo "Cada video procesado tiene su propia carpeta '${BASENAME}_output/' con:"
echo "  - Video convertido (.mov)"
echo "  - Archivos de audio (.wav) según modo seleccionado"
echo "  - Original archivado en 'original/'"
if [ "$VIDEO_MODE" -eq 2 ]; then
    echo "Video convertido a DNxHR-SQ."
else
    echo "Video copiado sin cambios de codec."
fi
echo "Conversion completada."
