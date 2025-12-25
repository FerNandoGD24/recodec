# recodec.sh

Convierte archivos de video `.mp4` o `.mkv` a formato `.mov` compatible con DaVinci Resolve en Linux,  
usando DNxHR SQ (video) y PCM 16-bit 48 kHz (audio).

se toma el audio del video y da a elegir entre **5 modos de audio**(cada pista es un archivo de audio independiente:
- duplicar la cantidad de pistas en mono (1 pista = 1 pista mono solo con audio izquerda + 1 pista mono solo con audio derecha) 
- pistas mono
- pistas stereo
- comprimir audio en una pista mono
- comprimir audio en una pista stereo

Este comportamiento evita problemas de reconocimiento de audio en DaVinci Resolve,  
que en Linux solo acepta ciertos formatos y no maneja bien pistas estéreo o multicanal en contenedores como MP4/MKV.

## Requisitos

- `bash` (4.0+)
- `ffmpeg` y `ffprobe` con soporte para:
  - Códec de video `dnxhd` (perfil `dnxhr_sq`)
  - Formato `mov`
  - Filtros de audio `pan`
- `util-linux` (para `taskset`)
- Sistema Linux

Este script **no incluye ni distribuye códecs**. Solo utiliza las capacidades de tu instalación local de `ffmpeg`.

## Instalación de dependencias

Ejecuta el comando correspondiente a tu distribución:

**Debian, Ubuntu y derivados:**

```bash
sudo apt update && sudo apt install ffmpeg bash coreutils util-linux
```

**Arch Linux, EndeavourOS y derivados:**

```bash
sudo pacman -Syu ffmpeg bash coreutils util-linux
```

**Fedora, RHEL, AlmaLinux y derivados:**

```bash
sudo dnf install ffmpeg ffmpeg-free bash coreutils util-linux
```

**openSUSE Tumbleweed:**

```bash
sudo zypper install ffmpeg bash coreutils util-linux
```

> **Importante**: El soporte para el códec `dnxhd` (usado por DNxHR SQ) **no siempre está incluido** en las versiones de `ffmpeg` distribuidas oficialmente.  
> Para verificar si tu instalación lo soporta, ejecuta:
> ```bash
> ffmpeg -h encoder=dnxhd
> ```
> Si no aparece información, es posible que necesites una compilación de `ffmpeg` con soporte habilitado.  
> Una guía confiable para compilarlo desde el código fuente se encuentra en:  
> https://trac.ffmpeg.org/wiki/CompilationGuide

## Uso

```bash
./recodec.sh *.mkv *.mp4
```

- Procesa solo archivos `.mp4` y `.mkv` (no distingue mayúsculas/minúsculas).
- Omite archivos si ya existe un `.mov` con el mismo nombre.
- Tras una conversión exitosa, mueve el archivo original a la carpeta `input/`.
- Muestra progreso en tiempo real y un resumen final con tiempos por archivo.


```bash
./recodec.sh *.mp4
```

- Procesa solo archivos `.mp4` (no distingue mayúsculas/minúsculas).
- Omite archivos si ya existe un `.mov` con el mismo nombre.
- Tras una conversión exitosa, mueve el archivo original a la carpeta `input/`.
- Muestra progreso en tiempo real y un resumen final con tiempos por archivo.


```bash
./recodec.sh *.mkv
```

- Procesa solo archivos  `.mkv` (no distingue mayúsculas/minúsculas).
- Omite archivos si ya existe un `.mov` con el mismo nombre.
- Tras una conversión exitosa, mueve el archivo original a la carpeta `input/`.
- Muestra progreso en tiempo real y un resumen final con tiempos por archivo.

## Comportamiento del sistema

- Usa ~70 % de los núcleos CPU disponibles (mínimo 2).
- Ejecuta `ffmpeg` con prioridad reducida (`nice`, `ionice`) y afinidad de CPU (`taskset`),
  para no interferir con otras tareas del sistema.
