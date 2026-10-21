# Santo Video Player — Build nativo (MinGW-w64)

Build **verificado com sucesso** nesta sessão. O módulo `glfilter_crt` (shader
CRT) e o vout `gl` (com a integração `--gl-crt`) **compilam e linkam** num build
nativo do VLC 4.0 no Windows, **sem MSVC e sem admin**.

## Resultado (binários gerados)

| DLL | O quê |
|---|---|
| `D:\vlc-build\modules\libglfilter_crt_plugin.dll` | Filtro CRT (`filter_crt.c`) |
| `D:\vlc-build\modules\libgl_plugin.dll` | vout `gl` (inclui `vout_helper.c` com `--gl-crt`) |
| `D:\vlc-build\src\libvlccore.dll` | núcleo do VLC |

O shader está embutido no binário (confirmado: `crt_scanline_strength`,
`crt_mask_strength`, `gl_FragColor` presentes na DLL).

## Toolchain (tudo user-level, sem admin)

```powershell
scoop install mingw ninja pkg-config        # gcc 16.2 / ninja / pkg-config
& "<python>.exe" -m pip install meson       # meson >= 1.10
```

## GLEW (só cabeçalhos — o vout GL carrega funções dinamicamente)

```powershell
Invoke-WebRequest "https://github.com/nigels-com/glew/releases/download/glew-2.3.1/glew-2.3.1.tgz" -OutFile glew.tgz
tar -xzf glew.tgz
# copiar glew-2.3.1/include/GL/{glew.h,wglew.h} para contrib/include/GL/
```

## Native file do meson (`contrib-native.ini`)

```ini
[properties]
contrib_dir = 'D:/vlc-contrib'
contrib_incdir = 'D:/vlc-contrib/include'
contrib_libdir = 'D:/vlc-contrib/lib'
```

## Configurar + compilar

```powershell
$env:PATH = "$env:USERPROFILE\scoop\apps\mingw\current\bin;$env:USERPROFILE\scoop\shims;$env:PATH"
cd D:\vlc-src
meson setup D:\vlc-build --native-file D:\vlc-native.ini --buildtype=release \
  -Dtests=disabled -Davcodec=disabled -Davformat=disabled -Dswscale=disabled \
  -Dpng=disabled -Dzvbi=disabled -Dlua=disabled -Dpostproc=disabled \
  -Dqt=disabled -Dvulkan=disabled -Dnsis=disabled -Dwix=disabled
ninja -C D:\vlc-build modules/libglfilter_crt_plugin.dll modules/libgl_plugin.dll
```

> ⚠️ **Importante:** o caminho do workspace (`D:\vscode temp\...`) tem espaço, o
> que quebra o `windres` do MinGW (bug conhecido). Por isso o código-fonte foi
> copiado para `D:\vlc-src` (sem espaço) antes do build. Manter o build em um
> caminho sem espaço.

## O que ainda falta para um player funcional

## Habilitar FFmpeg (decodificação real) — feito

O FFmpeg foi compilado nativamente (estático, decoders/demuxers apenas, sem
dependências externas) e integrado:

```powershell
# FFmpeg 9.0 (versão pinada pelo contrib do VLC)
Invoke-WebRequest "https://ffmpeg.org/releases/ffmpeg-9.0.tar.xz" -OutFile ffmpeg-9.0.tar.xz
tar -xf ffmpeg-9.0.tar.xz
# configure (via git-bash), perfil mínimo do contrib:
#   --enable-static --disable-shared --disable-doc --disable-debug
#   --disable-avdevice --disable-devices --disable-avfilter --disable-filters
#   --disable-network --disable-encoders --disable-muxers --disable-programs
#   --disable-bsfs --enable-bsf=vp9_superframe --disable-bzlib --disable-lzma
#   --disable-zlib --disable-iconv --disable-libvpx --disable-libgsm
#   --disable-libopenjpeg --disable-avisynth --disable-nvenc
bash -c 'cd /d/ffmpeg-9.0 && ./configure --prefix=/d/ffmpeg-prefix ...'
bash -c 'cd /d/ffmpeg-9.0 && make -j16 && make install'
# corrigir prefix dos .pc (MSYS -> Windows) e apontar o native file p/ D:/ffmpeg-prefix
```

Depois, reconfigure o VLC **sem** os `-D...=disabled` de `avcodec/avformat/
swscale` e com `PKG_CONFIG_PATH=D:/ffmpeg-prefix/lib/pkgconfig`.

## O que ainda falta

1. **UI**: o build atual não inclui Qt (fica só `vlc.exe`/`libvlc` sem interface
   gráfica). Para janela/GUI: compilar o Qt via contrib, ou escrever um
   frontend mínimo sobre `libvlc`.
2. Aplicar a receita "light" (`LIGHT_BUILD.md`) no build final.

A estratégia de "enxugar" continua a mesma.
