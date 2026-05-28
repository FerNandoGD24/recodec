# Script de preparación de video para DaVinci Resolve

## Descripción
Script de bash que prepara archivos de video para su importación en DaVinci Resolve. Reempaqueta el material a contenedor `.mov`, mantiene el códec de video original, extrae cada pista de audio a un archivo `.wav` independiente (PCM 16 bit, 48 kHz, estéreo) y archiva los archivos originales en una subcarpeta de respaldo.

## Propósito
Estandarizar la estructura de los archivos de entrada para DaVinci Resolve. La separación de video y audio en contenedores `.mov` y `.wav` facilita la gestión en la línea de tiempo y reduce errores de decodificación o sincronización frecuentes en entornos Linux. El script prioriza la copia directa del flujo de video para evitar generaciones de compresión adicionales.

## Dependencias
- `bash`
- `ffmpeg` y `ffprobe`
- `coreutils` (`awk`, `nice`, `taskset`, `ionice`, `seq`)
- Utilidades estándar: `find`, `sort`, `date`

## Integración de FFmpeg en DaVinci Resolve (Linux)
La versión oficial de DaVinci Resolve para Linux no incluye FFmpeg en su instalación base. Para ampliar la compatibilidad de decodificación, debes integrar las bibliotecas de FFmpeg del sistema:

- **Arch Linux / Manjaro (AUR):** Instala `davinci-resolve` o `davinci-resolve-studio`. Los paquetes del AUR suelen incluir hooks o instrucciones para enlazar las bibliotecas de `ffmpeg` del sistema con el directorio de Resolve.
- **Ubuntu / Debian:** Instala `ffmpeg` desde los repositorios oficiales. Crea enlaces simbólicos de `libavcodec.so`, `libavformat.so`, `libavutil.so`, etc., en `/opt/resolve/libs/`, o copia los binarios `ffmpeg` y `ffprobe` en `/opt/resolve/bin/`.
- **Fedora / openSUSE / Otras:** Instala FFmpeg mediante el gestor de paquetes correspondiente. Luego, exporta `LD_LIBRARY_PATH` apuntando a las rutas de las bibliotecas de FFmpeg antes de ejecutar Resolve, o modifica el script de lanzamiento de Resolve para incluir `LD_PRELOAD` con las bibliotecas del sistema.

Consulta la documentación de Blackmagic Design para verificar la estructura exacta de directorios según tu versión.

## Uso
Ejecuta el script desde la terminal. Puedes pasar rutas de archivos como argumentos o dejar que detecte automáticamente los videos compatibles en el directorio actual.

```bash
./script.sh [archivo1.mp4 archivo2.mkv ...]
