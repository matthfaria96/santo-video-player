# Santo Video Player — VLC "light" com shaders CRT (nativos, só no vídeo)

## 1. Resumo executivo

Objetivo: partir do [VLC](https://github.com/videolan/vlc) e criar uma versão
enxuta ("light") que aplica **shaders CRT** — vindos do ecossistema usado pelo
[ShaderGlass](https://github.com/mausimus/ShaderGlass) — **apenas sobre o vídeo**,
nunca sobre a área de trabalho / sistema inteiro.

O ponto de integração nativo e correto é o **pipeline OpenGL do próprio VLC**
(a cadeia de filtros `vlc_gl_filter` do video output `gl`). Escrevi um módulo
`glfilter_crt` que roda como um estágio da cadeia de filtros do vídeo — ou seja,
o shader só enxerga o framebuffer do vídeo. Isso é estruturalmente diferente do
ShaderGlass, que é um *overlay* sobre o desktop inteiro.

**Estado atual:** repositórios clonados, arquitetura mapeada, primeiro módulo
implementado (`filter_crt.c`) e conectado aos dois sistemas de build do VLC
(meson e autotools). **Falta compilar** — ver seção 6.

---

## 2. O que já está feito

- Clonados `videolan/vlc` e `mausimus/ShaderGlass` (shallow) em:
  - `vlc/`
  - `shaderglass/`
- Mapeamento confirmado das duas bases:
  - **VLC**: a saída OpenGL (`modules/video_output/opengl/`) tem uma cadeia de
    filtros com API pública `struct vlc_gl_filter_ops`
    (`include/vlc_opengl_filter.h`). Filtros são módulos VLC registrados com
    `set_capability("opengl filter", 0)` e carregados por nome via
    `vlc_gl_filters_Append()`. Exemplos: `filter_draw.c` (desenha o vídeo),
    `renderer.c` (escala final), `pl_scale.c`, `gladjust.c`.
  - **ShaderGlass**: app C++/DirectX que **compila shaders libretro slang
    (GLSL) para HLSL/DXBC** e os roda como overlay. Os shaders CRT que ele
    distribui vêm do repositório
    [libretro/slang-shaders](https://github.com/libretro/slang-shaders)
    (ex.: `crt/shaders/crt-easymode.slang`, `crt-royale`, `crt-geom`, etc.).

### Arquivos alterados/criados

| Arquivo | O que faz |
|---|---|
| `vlc/modules/video_output/opengl/filter_crt.c` | **Novo.** Filtro GL `crt` (port do crt-easymode). |
| `vlc/modules/video_output/opengl/meson.build` | Registra o módulo `glfilter_crt`. |
| `vlc/modules/video_output/opengl/Makefile.am` | Registra `libglfilter_crt_plugin.la`. |
| `vlc/modules/video_output/opengl/vout_helper.h` | Adiciona a opção `--gl-crt`. |
| `vlc/modules/video_output/opengl/vout_helper.c` | Insere `"crt"` na cadeia, antes do `renderer`. |

---

## 3. Arquitetura da integração

```
vídeo decodificado
      │
      ▼
cadeia de filtros do vout "gl"  (vout_helper.c: CreateFilters)
      │
      ├── [pl_scale?]  (upscaler/downscaler, se configurado)
      ├── ★ crt        ← NOVO: shader CRT roda AQUI (só no vídeo)
      └── renderer     (escala final para a janela/tela)
```

- O filtro é **não-blend**: lê a textura de entrada (`vlc_texture(tex_coords)`)
  e desenha no seu próprio framebuffer. Como ele entra **antes do `renderer`**,
  ele afeta somente o conteúdo de vídeo — nunca o resto da interface/sistema.
- **Ativação:** `--vout=gl --gl-crt` (ou `--vout=gles2 --gl-crt` em dispositivos
  GLES). Parâmetros expostos com prefixo `crt-*` (ex.: `--crt-scanline-strength=0.8`).

### Por que OpenGL e não o overlay do ShaderGlass?

O ShaderGlass é um overlay de desktop (captura a tela e re-desenha com shader).
Isso "afeta o computador inteiro" e exigiria portar toda a captura de tela do
Windows. A integração no VLC é mais simples, mais leve e faz exatamente o que
foi pedido: **shader só no vídeo**, nativo, sem captura de tela.

---

## 4. O shader (adaptado do crt-easymode)

Base: **crt-easymode** ("CRT Shader by EasyMode", GPL), do mesmo ecossistema
libretro/slang que o ShaderGlass distribui. Mantive os elementos clássicos
(**scanlines**, **máscara RGB aperture-grille**, **gamma in/out**, **brightness
boost**) num único passo, mas **adaptei para playback de vídeo moderno**:

- O crt-easymode original calcula a frequência das scanlines em **resolução da
  fonte**, o que só fica visível ao *upscalar* conteúdo retrô (240p → 1080p).
  Num vídeo já em resolução nativa (1:1), as scanlines desaparecem.
- Por isso o filtro usa **scanlines e máscara em espaço de tela**
  (`gl_FragCoord`) com **passo fixo configurável** — visível em qualquer
  resolução. (A versão "responsive" fiel ao crt-easymode/geom/royale, com
  upscaling inteiro, fica como etapa seguinte.)

Tradução slang/GLSL 450 → dialeto GLSL do VLC:

| slang (ShaderGlass/libretro) | VLC |
|---|---|
| `texture(Source, c)` | `vlc_texture(c)` (gerado pelo sampler do VLC) |
| `params.*` (push constant) | `uniform float crt_*` |
| `FragColor` (GLSL 450 `out`) | `gl_FragColor` (GLES2/GLSL 120, igual ao `filter_draw.c`) |

São **8 parâmetros** expostos como opções VLC (`crt-gamma-in`,
`crt-scanline-strength`, `crt-scanline-period`, `crt-mask-strength`,
`crt-mask-size`, etc.).

**Verificação feita (2 camadas):**
1. **Compila** — os shaders (vertex e fragment) extraídos de `filter_crt.c` por
   `tools/extract_shader.js` passam no `glslang` 16.6.0 em **GLSL ES 1.00**
   (`#version 100`) e **GLSL 1.20** (`#version 120`) — exit 0, sem diagnóstico.
2. **Efeito correto** — `tools/crt_reference.py` reimplementa o mesmo GLSL em
   numpy; `tools/verify_effect.py` confirma numericamente (PASS) que surgem
   **scanlines** (linhas claras/escuras alternadas) e a **máscara RGB** (colunas
   R/G/B alternadas) sobre uma imagem branca.

---

## 5. Estratégia "VLC light" (próxima etapa)

> Receita concreta (flags meson prontas) em **[`LIGHT_BUILD.md`](LIGHT_BUILD.md)**.

O VLC já é modular; "enxugar" = **não compilar** o que não se usa. Não precisa
remover código-fonte; basta configurar o build. Caminhos (dependem do método de
build — ver seção 6):

1. **Desativar demuxers/codecs/streaming que ninguém usa** via flags de
   configuração (ex.: desligar `--disable-…` para protocolos de rede,
   chromecast, skins, lua, SDL, etc.).
2. **Meson**: reduzir a lista `vlc_modules` (ex.: não construir os `access_*`,
   `demux_*`, `codec_*` não desejados) e as features opcionais.
3. **Enxugar a UI**: para uma versão realmente "light", usar a interface mínima
   (sem Qt/skins) ou manter apenas o `libvlc` + um frontend próprio.
4. **Manter** o que importa: `libvlc`, o vout `gl`, o filtro `crt`, e os
   codecs de vídeo/áudio essenciais.

Essa etapa precisa de uma lista concreta de "o que remover", que depende do que
o usuário considera "ninguém usa" — vou propor uma lista e validar.

---

## 6. Pré-requisitos de build (✅ resolvido: build nativo funciona)

Inicialmente a máquina não tinha toolchain C/C++. **Resolvi sem admin**
instalando via scoop/pip: **MinGW-w64 (gcc 16.2) + ninja + meson + pkg-config**
(+ os cabeçalhos GLEW, que o vout `gl` usa só como header).

**Resultado verificado:** o `glfilter_crt` e o vout `gl` **compilam e linkam**
num build nativo do VLC 4.0 (meson+ninja), gerando `libglfilter_crt_plugin.dll`
e `libgl_plugin.dll`. Passo a passo completo em **[`BUILD.md`](BUILD.md)**.

O que ainda falta para um **player funcional** (não só o módulo CRT compilando):
compilar o **FFmpeg** via `contrib` (habilitar `avcodec/avformat/swscale`) e uma
UI. O build mínimo atual desliga o FFmpeg de propósito — serve para provar a
integração, não para decodificar vídeo ainda.

---

## 7. Licenciamento (importante)

- **VLC**: GPL-2.0+ / LGPL-2.1+ (core é LGPL; módulos GPL).
- **crt-easymode** (e a maioria dos shaders CRT): **GPL** (alguns são MIT/BSD,
  ver cada arquivo no slang-shaders).
- **ShaderGlass (app)**: GPL-3.0.

Como os shaders são **GPL** e o filtro que os incorpora é **GPL-2**, misturar
GPL-3 ↔ GPL-2 pode ser incompatível em distribuição. Para um projeto pessoal/
fork isso é menos crítico, mas para **distribuir** convém: (a) usar apenas
shaders sob licença compatível (MIT/BSD/GPL-2) ou (b) relicenciar/reescrever.
O `filter_crt.c` que escrevi está como LGPL-2.1 (padrão do diretório), mas como
**embute** o crt-easymode (GPL), o conjunto efetivo deve ser tratado como GPL —
vou ajustar o cabeçalho de licença para GPL-2+ antes de distribuir.

---

## 8. Próximos passos (ordem sugerida)

1. **Instalar toolchain** (seção 6) — pré-requisito para tudo.
2. Compilar o VLC (primeiro sem alterações) para ter uma baseline.
3. Compilar com o `glfilter_crt` e validar `--vout=gl --gl-crt`.
4. Ajustar o GLSL se o dialeto do contexto (GLES2 vs desktop GL) reclamar.
5. Definir e aplicar a lista "light" de módulos a remover (seção 5).
6. (Opcional) Filtro "responsive" para scanlines pixel-perfect na resolução da
   tela, e port de mais shaders (crt-geom, crt-royale multi-pass).
7. Revisão de licenciamento antes de distribuir.

---

## 9. Como testar (depois de compilado)

```bash
vlc --vout=gl --gl-crt video.mp4
vlc --vout=gl --gl-crt --crt-scanline-strength=0.8 --crt-mask-strength=0.5 video.mp4
```

O efeito aparece **somente no vídeo**; menus/janela do VLC e o restante do
sistema ficam intocados.
