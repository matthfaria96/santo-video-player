# Santo Video Player

Player de vídeo nativo para Windows (Win32 + libvlc) com **shaders CRT** (retrô,
estilo TV de tubo: scanlines + máscara RGB) aplicados **somente sobre o vídeo** —
nunca sobre a área de trabalho ou o sistema inteiro.

O efeito CRT roda dentro do pipeline OpenGL do próprio VLC (um filtro
`glfilter_crt`), e não como um overlay de desktop.

## Recursos

- Tema escuro, controles completos: abrir, playlist (arrastar vários arquivos),
  play/pause/parar, anterior/próxima, barra de progresso + tempo, volume/mudo,
  tela cheia.
- **Efeitos CRT** com presets (Sem shader / Clássico / Suave / Forte / Só
  scanlines / Tubo curvo) + sliders de scanlines e máscara. O preset "Tubo
  curvo" aplica curvatura de TV de tubo com bordas pretas nas laterais.
- Velocidade de reprodução, legendas automáticas (.srt/.sub/.ass), repetição
  (uma/todas), proporção (original/preencher/16:9/4:3/1:1), captura de tela.
- Persistência de janela/volume/efeito (arquivo `SantoVideoPlayer.ini`).
- Atalhos de teclado completos (veja `LEIA-ME.txt` na pasta do player).

## Estrutura

```
gui/                  frontend Win32 (santo-player.cpp) + build-gui.ps1
vlc-patches/          integração do shader CRT no VLC
  filter_crt.c        filtro OpenGL "crt" (shader CRT)
  crt-integration.patch   patch aplicado sobre o VLC (meson/autotools)
docs/                 BUILD.md, LIGHT_BUILD.md, PLANO.md (documentação)
tools/                ferramentas de verificação do shader (glslang/numpy)
```

## Como funciona

O shader é um módulo `glfilter_crt` do VLC que roda como um estágio da cadeia de
filtros OpenGL do video output `gl`, **antes** do renderer final. Ele só enxerga
o framebuffer do vídeo.

Ativação: `--vout=gl --gl-crt` (+ parâmetros `--crt-scanline-strength`,
`--crt-mask-strength`, `--crt-scanline-period`, `--crt-gamma-in`, etc.).

## Build

### 1. GUI (frontend)

Requer o toolchain MinGW-w64 e o SDK do libvlc (VLC 4.0):

```powershell
# gui/build-gui.ps1
g++ santo-player.cpp -o SantoVideoPlayer.exe `
  -I D:/vlc-install/sdk/include D:/vlc-install/libvlc.dll.a `
  -lcomdlg32 -lgdi32 -luser32 -lole32 -lshell32 `
  -mwindows -municode -static-libgcc -static-libstdc++ -std=c++17
```

### 2. Módulo CRT no VLC

Clone o VLC 4.0, aplique o patch e compile os módulos:

```bash
cd vlc
git apply vlc-patches/crt-integration.patch   # ou copie filter_crt.c e edite manualmente
meson setup build --buildtype=release ...     # flags do "light build" em docs/LIGHT_BUILD.md
ninja -C build modules/libgl_plugin.dll modules/libglfilter_crt_plugin.dll
```

O patch aplica:
- `filter_crt.c` — novo filtro (shader CRT adaptado do crt-easymode, GPL).
- `filters.c` / `filter.c` — correção para filtros antes do renderer
  (evita re-inicializar framebuffers já prontos — corrige um crash).
- `vout_helper.c/.h` — opção `--gl-crt` e inserção do filtro na cadeia.
- `meson.build` / `Makefile.am` — registro do módulo.

## Licença

- GUI e filtro CRT: **GPL-2.0+** (o shader deriva do crt-easymode, GPL).
- O VLC em si é LGPL/GPL; veja os termos do projeto VLC.
