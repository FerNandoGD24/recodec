# Media Converter - ProRes 422 HQ & WAV

Convierte videos a ProRes 422 HQ y audios a WAV estéreo 24-bit, optimizado para DaVinci Resolve.

## Requisitos

- `ffmpeg`
- `ffprobe`

## Uso

```bash
./convert_media.sh [carpeta_entrada] [carpeta_salida_default]
```

### Ejemplos

Procesar carpeta actual:
```bash
./recodec.sh
```

Procesar carpeta específica:
```bash
./recodec.sh /ruta/videos
```

## Formatos soportados

### Video
mp4, mkv, avi, m4v, webm, flv, wmv, ts, m2ts, mts, mov

### Audio
mp3, aac, flac, ogg, wma, m4a, opus, wav

## Características

- Conversión de videos a **ProRes 422 HQ** (10-bit yuv422p10le)
- Extracción automática de todas las pistas de audio como **WAV estéreo 24-bit**
- Conserva archivos originales en carpeta `originals/`
- Salida optimizada para DaVinci Resolve
- Procesamiento por lotes

## Estructura de salida

```
output/
├── video/
│   ├── *.mov                (ProRes 422 HQ)
│   ├── audio/
│   │   └── *_trackN.wav     (Pistas de audio extraídas)
│   └── originals/           (Videos originales)
└── audio/
    ├── *.wav                (Audios convertidos)
    └── originals/           (Audios originales)
```

## Codecs utilizados

| Tipo | Codec | Perfil | Formato píxel | Tasa muestreo | Profundidad |
|------|-------|--------|---------------|---------------|------------|
| Video | ProRes | 422 HQ (3) | yuv422p10le | - | 10-bit |
| Audio | PCM | - | - | 48000 Hz | 24-bit |

## Configuración

Edita las variables al inicio del script:

```bash
INPUT_DIR="${1:-.}"           # Carpeta entrada (argumento 1)
OUTPUT_DIR="output"           # Carpeta salida
VIDEO_DIR="$OUTPUT_DIR/video" # Salida videos
AUDIO_DIR="$OUTPUT_DIR/audio" # Salida audios
```

## Compatibilidad

- DaVinci Resolve: Totalmente compatible
- Final Cut Pro: Compatible
- Adobe Premiere: Compatible

## Notas

- Los archivos originales se mueven a la carpeta `originals/`
- Los WAV ya existentes en la entrada se saltan
- El script registra cada operación completada
- Usa `-loglevel warning` para minimizar output de ffmpeg

## Solución de problemas

### ffmpeg: comando no encontrado
```bash
sudo apt install ffmpeg  # Ubuntu/Debian
brew install ffmpeg      # macOS
```

### Permisos denegados
```bash
chmod +x convert_media.sh
```

### Espacio en disco insuficiente
Asegúrate de tener espacio libre para los videos procesados (aprox. 2x el tamaño original)

## Licencia

MIT

## Autor

Conversión de medios optimizada para post-producción
