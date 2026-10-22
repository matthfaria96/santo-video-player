# Santo Video Player

Player de vídeo com **shaders CRT** (retrô, estilo TV de tubo: scanlines,
máscara de fósforo, vidro curvo e moldura) aplicados **somente sobre o vídeo** —
nunca sobre a área de trabalho ou o sistema inteiro. Duas versões:

- **macOS** (`macos/`): SwiftUI + libmpv + Metal. Abre praticamente qualquer
  formato; efeito em tempo real, faixas de áudio e legendas, PiP, continuar de
  onde parou, interface em vidro (Liquid Glass no macOS 26+).
- **Windows** (`gui/` + `vlc-patches/`): Win32 + libvlc 4.0 com o filtro OpenGL
  `glfilter_crt`.

Os dois usam o mesmo modelo de tubo (ver "Efeito CRT" abaixo).

## macOS

```bash
cd macos
scripts/build-app.sh            # gera build/Santo Video Player.app (universal)
scripts/build-app.sh --install  # e copia para /Applications
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Requer macOS 15+ e o Xcode instalado (as macros do SwiftUI não vêm nas
Command Line Tools). A primeira compilação baixa o MPVKit (~200 MB).

**Motor**: libmpv + FFmpeg ([MPVKit](https://github.com/mpvkit/MPVKit), estático
e universal). O mpv decodifica (com VideoToolbox quando dá) e desenha cada frame
via OpenGL numa IOSurface; o Metal lê a mesma IOSurface, sem cópia, e aplica o
shader CRT. Abre praticamente tudo: MKV, MP4, MOV, AVI, WebM, TS, FLV, WMV…
com H.264, HEVC, AV1, VP9, MPEG-4, áudio AAC/AC3/DTS/Opus/FLAC etc.

- **Abre de tudo**: arquivos, **pastas** (vira playlist em ordem natural:
  Ep 2 antes de Ep 10), playlists `.m3u`, e **URLs** (⌘U: HTTP, HLS `.m3u8`,
  RTSP…). "Abrir com" do Finder funciona com MKV, AVI, WebM etc. HDR10 é
  convertido para a tela (tone mapping do mpv).
- **Ajustes** (⌘,), no padrão do MacDash: **Geral** (layout Moderno ou
  Clássico com prévia animada, idioma do app, tela inicial), **Reprodução**
  (continuar de onde parou, intervalo de avanço, idioma do áudio, decodificação
  por hardware), **Legendas** (idioma preferido, legenda ao lado do vídeo,
  aparência com amostra ao vivo) e **Sobre** (versão, licença, licenças de
  código aberto, witchmymac.com).
- **Faixas de áudio** (menu na barra, B alterna) e **legendas** embutidas ou
  em arquivo (`.srt`, `.ass`, `.vtt`, `.sub`, `.sup`…). Arquivos ao lado do vídeo
  com o mesmo nome carregam e ativam sozinhos; o encoding é detectado. Legenda
  nítida sobre a TV ou "dentro da tela" com o estilo ASS original e o efeito CRT.
  Atraso com G/H.
- **Continuar de onde parou** e tela inicial com **Continuar assistindo**
  (capa, progresso, tempo restante). ⇧⌘← volta ao início.
- **Prévia em miniatura** ao passar o mouse na barra de tempo.
- **Picture in Picture** (⌥⌘P) com o efeito CRT; as legendas vão junto.
- **Teclas de mídia** e Central de Controle (Now Playing com capa e posição).
- **Efeitos CRT** (⌘E, ⌘0…⌘7): 8 presets com prévia ao vivo do frame atual e
  sliders em tempo real. O "TV com Gabinete" (piano black, minimalista) muda
  conforme o vídeo: no 4:3 as faixas laterais viram o gabinete inteiro (grade
  de alto-falante, botões e LED); no 16:9 fica só uma moldura fina abraçando a
  imagem, com preto puro em volta — inclusive em tela cheia.
- Velocidade 0,25×–3× com correção de tom, playlist, repetição, preencher tela,
  quadro a quadro, captura com o efeito (⇧⌘S).
- Português e inglês (`Support/Localizations`; `scripts/extract-strings.py`
  lista as chaves a traduzir).
- Diagnóstico (⌥⌘I): fps, desenhos/s, tempo de GPU, frames perdidos.
  `SantoPlayer --bench imagem.png` mede o shader;
  `SantoPlayer --render-check imagem.png pasta/` renderiza todos os presets.

## Efeito CRT

O "TV de tubo" antigo encolhia o vídeo: a curvatura empurrava a imagem para fora
e pintava o resto de preto. O modelo novo:

- **Curvatura que não encolhe**: os pontos médios das bordas ficam no lugar; só
  os cantos saem do vidro, formando a silhueta convexa do tubo.
- **Vidro**: cantos arredondados, sombra interna nas bordas, reflexo especular e
  brilho no aro.
- **Moldura**: plástico acetinado nos cantos (e nas tarjas), iluminado pela luz
  da imagem que vaza pela borda.
- **Feixe**: scanlines cuja largura cresce com o brilho (média preservada),
  máscara de fósforo, halo, erro de convergência RGB, vinheta, ruído e faixa de
  interferência.

## Windows

O efeito CRT roda dentro do pipeline OpenGL do próprio VLC (um filtro
`glfilter_crt`), e não como um overlay de desktop.

### Recursos

- Tema escuro, controles completos: abrir, playlist (arrastar vários arquivos),
  play/pause/parar, anterior/próxima, barra de progresso + tempo, volume/mudo,
  tela cheia.
- **Efeitos CRT** com os mesmos 7 presets do macOS (Sem efeito / Clássico /
  Suave / Arcade / TV de Tubo / TV Antiga / Monitor PVM) + sliders de scanlines
  e máscara.
- Velocidade (botão na barra, `[` `]`), legendas automáticas (.srt/.sub/.ass),
  troca de faixa de legenda (botão CC ou V), carregar legenda (Ctrl+Shift+O),
  atraso da legenda (G/H), repetição (uma/todas),
  proporção (original/preencher/16:9/4:3/1:1), captura de tela.
- Persistência de janela/volume/efeito (arquivo `SantoVideoPlayer.ini`).
- Atalhos de teclado completos (veja `LEIA-ME.txt` na pasta do player).

### Estrutura

```
macos/                app macOS (SwiftPM): Sources/, Tests/, scripts/build-app.sh
gui/                  frontend Win32 (santo-player.cpp) + build-gui.ps1
vlc-patches/          integração do shader CRT no VLC
  filter_crt.c        filtro OpenGL "crt" (shader CRT)
  crt-integration.patch   patch aplicado sobre o VLC (meson/autotools)
docs/                 BUILD.md, LIGHT_BUILD.md, PLANO.md (documentação)
tools/                ferramentas de verificação do shader (glslang/numpy)
```

### Como funciona

O shader é um módulo `glfilter_crt` do VLC que roda como um estágio da cadeia de
filtros OpenGL do video output `gl`, **antes** do renderer final. Ele só enxerga
o framebuffer do vídeo.

Ativação: `--vout=gl --gl-crt` (+ parâmetros `--crt-scanline-strength`,
`--crt-mask-strength`, `--crt-scanline-period`, `--crt-curvature`,
`--crt-glow`, `--crt-vignette`, `--crt-noise`, `--crt-tube`, `--crt-mask-type`,
`--crt-gamma-in`, etc.).

Para validar o GLSL depois de editar o filtro: `node tools/extract_shader.js`
e `glslangValidator tools/crt_gl120.frag tools/crt_es100.frag tools/crt_es100.vert`.

### Build

#### 1. GUI (frontend)

Requer o toolchain MinGW-w64 e o SDK do libvlc (VLC 4.0):

```powershell
# gui/build-gui.ps1
g++ santo-player.cpp -o SantoVideoPlayer.exe `
  -I D:/vlc-install/sdk/include D:/vlc-install/libvlc.dll.a `
  -lcomdlg32 -lgdi32 -luser32 -lole32 -lshell32 `
  -mwindows -municode -static-libgcc -static-libstdc++ -std=c++17
```

#### 2. Módulo CRT no VLC

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

- GUI e filtro CRT: **GPL-2.0+** (o shader deriva do crt-easymode, GPL; o app
  macOS usa o mesmo modelo e segue a mesma licença).
- App macOS: libmpv e FFmpeg via MPVKit (build LGPL), compatíveis com a GPL.
- O VLC em si é LGPL/GPL; veja os termos do projeto VLC.
