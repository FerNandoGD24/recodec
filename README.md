# recodec.sh

Convierte o extrae contenido de archivos `.mp4` y `.mkv` a un formato compatible con **DaVinci Resolve en Linux**,  
usando el códec de video **DNxHR SQ** (o copia directa) y audio **PCM 16-bit a 48 kHz**.

El script incluye un **menú interactivo** que permite configurar:

- **Modo de video**:  
  - Copiar sin recodificar (rápido, mismo codec).  
  - Recodificar a DNxHR-SQ (ideal para edición fluida en DaVinci).

- **Modo de audio** (5 opciones):  
  1. Separar cada canal en pistas mono independientes (ej. stereo → 2 archivos: izq + der).  
  2. Convertir cada pista a mono (mezclando canales).  
  3. Extraer cada pista como stereo.  
  4. Comprimir **todas las pistas** en un solo archivo **mono**.  
  5. Comprimir **todas las pistas** en un solo archivo **stereo**.

Este enfoque resuelve problemas comunes en DaVinci Resolve para Linux, que tiene limitaciones al leer audio multicanal o pistas estéreo dentro de contenedores como MP4 o MKV.

Además, ofrece un modo de **exportación rápida** (solo video, solo audio o ambos) sin generar el archivo `.mov` final.

---

## Requisitos

- `bash` 4.0 o superior  
- `ffmpeg` y `ffprobe` con soporte para:
  - Códec `dnxhd` (perfil `dnxhr_sq`)
  - Filtros de audio (`pan`)
  - Formato de salida `mov`
- `util-linux` (para el comando `taskset`)
- Sistema operativo Linux

Importante: Este script **no incluye ni distribuye códecs**. Depende exclusivamente de tu instalación local de `ffmpeg`.

---

## Instalación de dependencias

Ejecuta el comando correspondiente a tu distribución:

### Debian, Ubuntu y derivados
```bash
sudo apt update && sudo apt install ffmpeg bash coreutils util-linux
```

### Arch Linux, EndeavourOS y derivados
```bash
sudo pacman -Syu ffmpeg bash coreutils util-linux
```

### Fedora, RHEL, AlmaLinux y derivados
```bash
sudo dnf install ffmpeg ffmpeg-free bash coreutils util-linux
```

### openSUSE Tumbleweed
```bash
sudo zypper install ffmpeg bash coreutils util-linux
```

### Verificación de soporte DNxHR
Para confirmar que tu `ffmpeg` soporta DNxHR-SQ, ejecuta:
```bash
ffmpeg -h encoder=dnxhd
```
Si no muestra información, es posible que necesites compilar `ffmpeg` desde el código fuente.  
Consulta la guía oficial: [FFmpeg Compilation Guide](https://trac.ffmpeg.org/wiki/CompilationGuide)
 > Si la página no carga, desactiva temporalmente extensiones de privacidad (como JShelter o uBlock Origin) para este dominio. El sitio usa una protección anti-bot llamada Anubis que requiere JavaScript moderno.

Nota: El sitio puede requerir resolver un reto anti-bot (Anubis) al acceder desde ciertos entornos automatizados.

---

## Uso básico

Haz el script ejecutable:
```bash
chmod +x recodec.sh
```

Luego, ejecútalo con o sin argumentos:

```bash
./recodec.sh
```
- Si no se pasan archivos, busca automáticamente todos los `.mp4` y `.mkv` en el directorio actual.
- Muestra un menú interactivo para configurar opciones antes de procesar.

O especifica archivos manualmente:
```bash
./recodec.sh video1.mp4 clip2.mkv
```

---

## Comportamiento durante el procesamiento

- Omite archivos si ya existe un `.mov` con el mismo nombre base.
- Tras una conversión exitosa, **mueve el archivo original a la carpeta `input/`**.
- Muestra **progreso en tiempo real** durante la recodificación (solo en modo DNxHR).
- Al final, presenta un **resumen detallado**: archivos correctos, fallidos, tiempos de procesamiento e integridad verificada.

---

## Gestión de recursos del sistema

- Usa aproximadamente el **70 % de los núcleos CPU disponibles** (mínimo 2).
- Ejecuta `ffmpeg` con:
  - Prioridad reducida (`nice -n 10`)
  - Baja prioridad de E/S (`ionice -c 2 -n 7`)
  - Afinidad limitada a núcleos específicos (`taskset`)
- Esto evita que el sistema se vuelva inutilizable durante conversiones pesadas.
