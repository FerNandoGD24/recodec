# 🎬 recodec.sh

Script de bash para recodificación y exportación de archivos de video usando **FFmpeg**. Diseñado para preparar material de video para edición profesional, con soporte para múltiples formatos, modos de audio configurables, conversión HDR→SDR y uso controlado de recursos del sistema.

---

## ✨ Características

- **Recodificación a DNxHR-SQ** o copia directa del codec original
- **Extracción de audio** en múltiples modos (mono, stereo, por canal, mezclado)
- **Detección automática de pistas de audio silenciosas** para evitar exportar pistas vacías
- **Conversión HDR → SDR** con tone mapping Hable
- **Control de FPS** de salida (30 o 60 fps)
- **Uso eficiente de CPU**: limita hilos y prioridad del proceso (`nice`, `taskset`, `ionice`)
- **Reintento automático** en caso de error durante el procesamiento
- **Verificación de integridad** del archivo de salida
- **Menú interactivo** para configurar todas las opciones antes de procesar
- Procesamiento por **lote** (todos los videos del directorio actual) o por **archivos individuales**

---

## 📋 Requisitos

- **Bash** 4.0 o superior
- **FFmpeg** y **FFprobe** instalados y disponibles en el `PATH`
- `taskset` (parte de `util-linux`)
- `ionice` (parte de `util-linux`)
- `nproc`

En sistemas Debian/Ubuntu:

```bash
sudo apt install ffmpeg util-linux
```

---

## 🚀 Uso

### Procesar todos los videos del directorio actual

```bash
bash recodec.sh
```

### Procesar archivos específicos

```bash
bash recodec.sh video1.mp4 video2.mkv
```

Al ejecutar el script, se abre un **menú interactivo** que permite configurar las opciones antes de iniciar el procesamiento.

---

## ⚙️ Opciones del menú

| Opción | Descripción |
|--------|-------------|
| **Codec de video** | Mantener el codec original (copia rápida) o recodificar a DNxHR-SQ |
| **Modo de audio** | Ver tabla de modos abajo |
| **Fotogramas por segundo** | 60 fps o 30 fps |
| **Número de núcleos** | Ajusta cuántos núcleos de CPU usar (por defecto: 70% del total) |
| **Exportar** | Extraer solo video, solo audio, o ambos sin recodificar el video |
| **HDR → SDR** | Activa conversión con tone mapping Hable |

### Modos de audio

| Modo | Descripción | Ejemplo |
|------|-------------|---------|
| 1 | Separar en 2 pistas mono por canal | 4 canales → 8 archivos `.wav` |
| 2 | Una pista mono por cada canal | 4 pistas stereo → 4 archivos mono |
| 3 | Una pista stereo por cada pista (por defecto) | 4 pistas → 4 archivos stereo |
| 4 | Mezclar todo a 1 archivo mono | N pistas → 1 `.wav` mono |
| 5 | Mezclar todo a 1 archivo stereo | N pistas → 1 `.wav` stereo |

---

## 📁 Estructura de salida

Por cada archivo procesado se crea una carpeta `<nombre>_output/`:

```
video_output/
├── video.mov                        # Video recodificado (sin audio)
├── video_audio_track_0.wav          # Pista(s) de audio extraídas
├── video_audio_track_1.wav
└── original/
    └── video.mp4                    # Archivo original archivado
```

---

## 🔧 Formatos de entrada soportados

`mp4`, `mkv`, `mov`, `avi`, `mxf`, `m4v`, `ts`, `mts`, `m2ts`, `webm`, `flv`, `wmv`, `mpg`, `mpeg`, `vob`

---

## 📝 Notas

- El script usa `nice -n 10`, `taskset` e `ionice -c 2 -n 7` para no saturar el sistema durante el procesamiento.
- La detección de pistas silenciosas analiza hasta el 25% de la duración del video en bloques de 60 segundos. Una pista se considera vacía si su nivel RMS es menor a **-70 dB** en todos los bloques analizados.
- En caso de error, el script **reintenta automáticamente** y elimina archivos parciales antes de volver a intentarlo.
- Al finalizar, se muestra un **resumen** con archivos procesados correctamente, tiempos y errores.

---

## 📄 Licencia

MIT — libre para usar, modificar y distribuir.

sientete libre de modificarlo para complir con tus exigencias
