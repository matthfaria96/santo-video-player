# Santo Video Player — Receita de build "light"

Objetivo: reduzir o VLC ao essencial para um **player de vídeo local com shader
CRT**. Em vez de remover código-fonte (arriscado e difícil de manter), usamos as
flags de configuração do próprio VLC (meson) para **não compilar** o que ninguém
usa. Isso é mais seguro, mantém o fork atualizável e é o jeito "nativo" de
enxugar o VLC.

## Estratégia central: "FFmpeg primeiro"

O VLC vem com **dezenas de codecs/demuxers próprios** que duplicam o que o
FFmpeg (`avcodec` + `avformat` + `swscale`) já faz. Para a versão light:

- **Manter** FFmpeg (decodifica/demuxa praticamente tudo);
- **Desligar** os codecs/demuxers redundantes (vorbis, opus, flac, matroska,
  ogg, vpx, aom, dav1d, x264/x265, etc.);
- **Desligar** tudo que é streaming/rede/descoberta/visualização.

Isso corta dezenas de dependências externas e reduz muito o tamanho e o tempo
de build.

## Comando meson (flags do "light")

```bash
meson setup build --buildtype=release \
  # --- Streaming / rede (fora) ---
  -Dchromecast=disabled -Dadaptive=disabled -Dsrt=disabled -Drist=disabled \
  -Dlive555=disabled -Dshout=disabled -Dupnp=disabled -Dupnp_server=disabled \
  -Dmicrodns=disabled -Davahi=disabled -Dsmbclient=disabled -Dsmb2=disabled \
  -Ddsm=disabled -Dnfs=disabled -Dsftp=disabled -Dlibssh2=disabled \
  -Darchive=disabled -Dfreerdp=disabled -Dvnc=disabled -Dmtp=disabled \
  # --- TV / captura / legendas legadas (fora) ---
  -Dlibdvbpsi=disabled -Ddvbcsa=disabled -Dlibxml2=disabled \
  -Daribb24=disabled -Daribb25=disabled -Daribcaption=disabled -Daribsub=disabled \
  -Dzvbi=disabled -Dtelx=disabled -Dkate=disabled -Dtiger=disabled \
  # --- Descoberta / biblioteca de mídia (fora) ---
  -Dmedialibrary=disabled -Dvideolan_manager=false -Daddon_manager=false \
  # --- Visualização / áudio extra (fora) ---
  -Dgoom2=disabled -Dprojectm=disabled -Dvsxu=disabled \
  -Dfluidsynth=disabled -Dgme=disabled -Dsid=disabled -Dlibmodplug=disabled \
  -Drnnoise=disabled -Dcaca=disabled \
  # --- Codecs/demuxers redundantes (FFmpeg já cobre) ---
  -Dvorbis=disabled -Dopus=disabled -Dflac=disabled \
  -Dtheoraenc=disabled -Dtheoradec=disabled -Ddaaladec=disabled -Ddaalaenc=disabled \
  -Dvpx=disabled -Daom=disabled -Ddav1d=disabled -Drav1e=disabled \
  -Dx264=disabled -Dx265=disabled -Dx262=disabled \
  -Dfdk-aac=disabled -Dshine=disabled -Dtwolame=disabled \
  -Dmad=disabled -Dfaad=disabled -Dmpg123=disabled -Dopenapv=disabled \
  -Dspeex=disabled -Dspeexdsp=disabled -Dsamplerate=disabled -Dsoxr=disabled \
  -Dtaglib=disabled -Dlibchromaprint=disabled \
  -Dmatroska=disabled -Dogg=disabled -Ddvdnav=disabled -Ddvdread=disabled \
  -Dbluray=disabled \
  # --- Interface / scripts (mantém Qt) ---
  -Dskins2=disabled -Dncurses=disabled -Dlua=disabled -Ddbus=disabled \
  # --- Saída de vídeo: só OpenGL (precisa do "gl" para o CRT) ---
  -Dvulkan=disabled -Dlibplacebo=disabled -Dgles2=disabled
```

## O que se mantém (essencial)

| Componente | Por quê |
|---|---|
| `avcodec` / `avformat` / `swscale` | Decodificação e demux de quase todos os vídeos/áudios |
| `directx` / `d3d11va` / `dxva2` | Aceleração de vídeo por GPU no Windows |
| `wasapi` | Saída de áudio no Windows |
| `qt` | Interface gráfica (a maior dependência única; ver nota abaixo) |
| `freetype` / `fontconfig` / `harfbuzz` / `fribidi` / `libass` | Legendas |
| `png` / `jpeg` | Capas e imagens |
| vout `gl` + filtro `crt` | **A parte nova: shader CRT no vídeo** |

## Nota sobre o Qt (opcional, ultra-light)

O Qt é a maior dependência e o que mais pesa no build. Se quiser um player
**realmente** mínimo, dá para:

1. `-Dqt=disabled` (fica sem GUI → só `libvlc` + linha de comando), e
2. escrever um frontend próprio sobre o `libvlc` (Win32/GTK/Electron), que
   chama `libvlc` com `--vout=gl --gl-crt`.

Para a **primeira versão**, recomendo manter o Qt (mais rápido de validar) e
considerar o frontend próprio só depois que o efeito CRT estiver funcionando.

## Resultado esperado

- Build mais rápido (menos dependências para compilar no `contrib`);
- Binário e plugins visivelmente menores;
- Nenhuma funcionalidade relevante para "abrir um vídeo local e assistir com
  CRT" é perdida (FFmpeg cobre os codecs, Qt dá a janela, `gl` dá o vídeo).

## Pré-requisito (continua valendo)

Tudo acima depende de ter **toolchain C/C++** (Visual Studio Build Tools ou a
rota WSL/mingw) + o `contrib` do VLC. Sem isso, não dá para compilar — ver
`PLANO.md` §6.
