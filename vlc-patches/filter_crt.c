/*****************************************************************************
 * filter_crt.c : CRT shader OpenGL filter (scanlines + RGB aperture grille)
 *****************************************************************************
 * This filter applies a CRT retro shader to the video only, inside the
 * OpenGL video output filter chain. It is adapted from the "crt-easymode"
 * shader (libretro/slang-shaders, "CRT Shader by EasyMode") — keeping its
 * scanlines, RGB aperture-grille mask and gamma pipeline — but using
 * fixed-pitch, screen-space (gl_FragCoord) coordinates so the effect is
 * visible when playing modern content at its native resolution (a faithful
 * source-resolution port only shows scanlines when upscaling retro content).
 *
 * Original shader (crt-easymode, "CRT Shader by EasyMode"):
 *   https://github.com/libretro/slang-shaders/blob/master/crt/shaders/crt-easymode.slang
 *   (GPL, per the original file's license note; see that file for credits.)
 *
 * Because this source is derived from the GPL-licensed crt-easymode shader,
 * this module is distributed under the GPL (not LGPL), to match.
 *
 * Copyright (C) 2024 Santo Video Player
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_plugin.h>
#include <vlc_modules.h>
#include <vlc_opengl.h>
#include <vlc_opengl_filter.h>

#include "gl_api.h"
#include "gl_common.h"
#include "gl_util.h"
#include "sampler.h"

#define CRT_CFG_PREFIX "crt-"

/* Tunable parameters. The option name uses a hyphen, while the GLSL uniform
 * name uses an underscore (GLSL identifiers cannot contain hyphens). */
enum crt_param
{
    CRT_GAMMA_IN, CRT_GAMMA_OUT, CRT_BRIGHT_BOOST,
    CRT_SCANLINE_STRENGTH, CRT_SCANLINE_PERIOD, CRT_SCANLINE_BEAM,
    CRT_MASK_STRENGTH, CRT_MASK_SIZE,
    CRT_CURVATURE, CRT_GLOW, CRT_VIGNETTE, CRT_NOISE, CRT_TUBE, CRT_MASK_TYPE,
    CRT_PARAM_COUNT,
};

static const char *const crt_option_names[CRT_PARAM_COUNT + 1] = {
    "gamma-in", "gamma-out", "bright-boost",
    "scanline-strength", "scanline-period", "scanline-beam",
    "mask-strength", "mask-size", "curvature",
    "glow", "vignette", "noise", "tube", "mask-type",
    NULL,
};

static const char *const crt_uniform_names[CRT_PARAM_COUNT] = {
    "crt_gamma_in", "crt_gamma_out", "crt_bright_boost",
    "crt_scanline_strength", "crt_scanline_period", "crt_scanline_beam",
    "crt_mask_strength", "crt_mask_size", "crt_curvature",
    "crt_glow", "crt_vignette", "crt_noise", "crt_tube", "crt_mask_type",
};

struct sys {
    struct vlc_gl_api api;
    struct vlc_gl_sampler *sampler;

    GLuint program_id;
    GLuint vbo;

    GLint loc_vertex_pos;
    GLint loc_tex_coords_in;
    GLint loc_param[CRT_PARAM_COUNT];
    GLint loc_size, loc_time, loc_tc_origin, loc_tc_x, loc_tc_y;

    float params[CRT_PARAM_COUNT];
    float width, height;
    /* Affine map from the 0..1 output square to texture coordinates. */
    float tc_origin[2], tc_x[2], tc_y[2];
    unsigned frame;
};

static int
Draw(struct vlc_gl_filter *filter, const struct vlc_gl_picture *pic,
     const struct vlc_gl_input_meta *meta)
{
    (void) meta;

    struct sys *sys = filter->sys;
    const opengl_vtable_t *vt = &sys->api.vt;

    vt->UseProgram(sys->program_id);

    struct vlc_gl_sampler *sampler = sys->sampler;
    vlc_gl_sampler_Update(sampler, pic);
    vlc_gl_sampler_Load(sampler);

    vt->BindBuffer(GL_ARRAY_BUFFER, sys->vbo);

    if (pic->mtx_has_changed)
    {
        float coords[] = {
            0, 1,
            0, 0,
            1, 1,
            1, 0,
        };

        /* Transform coordinates in place */
        vlc_gl_picture_ToTexCoords(pic, 4, coords, coords);

        const float data[] = {
            -1,  1, coords[0], coords[1],
            -1, -1, coords[2], coords[3],
             1,  1, coords[4], coords[5],
             1, -1, coords[6], coords[7],
        };
        vt->BufferData(GL_ARRAY_BUFFER, sizeof(data), data, GL_STATIC_DRAW);

        /* Vertex order: (-1,1) (-1,-1) (1,1) (1,-1) */
        sys->tc_origin[0] = coords[2];             sys->tc_origin[1] = coords[3];
        sys->tc_x[0] = coords[6] - coords[2];      sys->tc_x[1] = coords[7] - coords[3];
        sys->tc_y[0] = coords[0] - coords[2];      sys->tc_y[1] = coords[1] - coords[3];
    }

    const GLsizei stride = 4 * sizeof(float);

    vt->EnableVertexAttribArray(sys->loc_vertex_pos);
    vt->VertexAttribPointer(sys->loc_vertex_pos, 2, GL_FLOAT, GL_FALSE, stride,
                            (const void *) 0);

    /* Texture coordinates are rebuilt in the fragment shader from the
     * tc_* uniforms, so the compiler may drop this attribute. */
    if (sys->loc_tex_coords_in != -1)
    {
        intptr_t offset = 2 * sizeof(float);
        vt->EnableVertexAttribArray(sys->loc_tex_coords_in);
        vt->VertexAttribPointer(sys->loc_tex_coords_in, 2, GL_FLOAT, GL_FALSE,
                                stride, (const void *) offset);
    }

    for (int i = 0; i < CRT_PARAM_COUNT; ++i)
        if (sys->loc_param[i] != -1)
            vt->Uniform1f(sys->loc_param[i], sys->params[i]);
    vt->Uniform2f(sys->loc_size, sys->width, sys->height);
    vt->Uniform1f(sys->loc_time, (float) (sys->frame++ % 216000u) / 60.f);
    vt->Uniform2f(sys->loc_tc_origin, sys->tc_origin[0], sys->tc_origin[1]);
    vt->Uniform2f(sys->loc_tc_x, sys->tc_x[0], sys->tc_x[1]);
    vt->Uniform2f(sys->loc_tc_y, sys->tc_y[0], sys->tc_y[1]);

    vt->Clear(GL_COLOR_BUFFER_BIT);
    vt->DrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    GL_ASSERT_NOERROR(vt);

    return VLC_SUCCESS;
}

static void
Close(struct vlc_gl_filter *filter)
{
    struct sys *sys = filter->sys;

    const opengl_vtable_t *vt = &sys->api.vt;
    vt->DeleteProgram(sys->program_id);
    vt->DeleteBuffers(1, &sys->vbo);

    free(sys);
}

static int
Open(struct vlc_gl_filter *filter, const config_chain_t *config,
     struct vlc_gl_sampler *sampler, struct vlc_gl_tex_size *size_out)
{
    struct sys *sys = filter->sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_EGENERIC;

    /* The filter keeps the input size: it runs at video resolution. */
    sys->width = size_out->width > 0 ? (float) size_out->width : 1.f;
    sys->height = size_out->height > 0 ? (float) size_out->height : 1.f;
    sys->tc_origin[0] = 0.f; sys->tc_origin[1] = 0.f;
    sys->tc_x[0] = 1.f; sys->tc_x[1] = 0.f;
    sys->tc_y[0] = 0.f; sys->tc_y[1] = 1.f;

    sys->sampler = sampler;

    int ret = vlc_gl_api_Init(&sys->api, filter->gl);
    if (ret != VLC_SUCCESS)
    {
        free(sys);
        return VLC_EGENERIC;
    }

    /* Non-blend filter: reads its input picture and draws to its own output
     * framebuffer. */
    filter->config.filter_planes = false;
    filter->config.blend = false;
    filter->config.msaa_level = 0;

    const opengl_vtable_t *vt = &sys->api.vt;

    config_ChainParse(filter, CRT_CFG_PREFIX, crt_option_names, config);
    for (int i = 0; i < CRT_PARAM_COUNT; ++i)
    {
        char varname[64];
        snprintf(varname, sizeof(varname), CRT_CFG_PREFIX "%s",
                 crt_option_names[i]);
        sys->params[i] = var_InheritFloat(filter, varname);
    }

    static const char *const VERTEX_SHADER_BODY =
        "attribute vec2 vertex_pos;\n"
        "attribute vec2 tex_coords_in;\n"
        "varying vec2 screen_pos;\n"
        "void main() {\n"
        "  gl_Position = vec4(vertex_pos, 0.0, 1.0);\n"
        "  screen_pos = vertex_pos;\n"
        "}\n";

    /* CRT picture tube (same model as the macOS player's Metal shader):
     *  - barrel warp that keeps the edge midpoints in place, so the picture
     *    keeps its size and only the corners leave the glass;
     *  - beam scanlines whose width grows with brightness (average preserved);
     *  - phosphor mask: aperture grille, slot mask or dot triads;
     *  - glow, RGB convergence error, vignette, noise and rolling band;
     *  - tube mode: rounded glass, inner edge shadow, reflections and a
     *    satin bezel in the trimmed corners, lit by the picture.
     * p uses y = -1 at the top of the screen. */
    static const char *const FRAGMENT_SHADER_BODY =
        "varying vec2 screen_pos;\n"
        "uniform float crt_gamma_in;\n"
        "uniform float crt_gamma_out;\n"
        "uniform float crt_bright_boost;\n"
        "uniform float crt_scanline_strength;\n"
        "uniform float crt_scanline_period;\n"
        "uniform float crt_scanline_beam;\n"
        "uniform float crt_mask_strength;\n"
        "uniform float crt_mask_size;\n"
        "uniform float crt_curvature;\n"
        "uniform float crt_glow;\n"
        "uniform float crt_vignette;\n"
        "uniform float crt_noise;\n"
        "uniform float crt_tube;\n"
        "uniform float crt_mask_type;\n"
        "uniform vec2 crt_size;\n"
        "uniform float crt_time;\n"
        "uniform vec2 crt_tc_origin;\n"
        "uniform vec2 crt_tc_x;\n"
        "uniform vec2 crt_tc_y;\n"
        "\n"
        "vec3 crt_fetch(vec2 s) {\n"
        "  s = clamp(s, 0.0, 1.0);\n"
        "  /* s: 0..1 with y = 0 at the top */\n"
        "  return vlc_texture(crt_tc_origin + s.x * crt_tc_x + (1.0 - s.y) * crt_tc_y).rgb;\n"
        "}\n"
        "vec3 crt_lin(vec3 c) { return pow(max(c, 0.0), vec3(crt_gamma_in)); }\n"
        "float crt_luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }\n"
        "float crt_hash(vec2 p) {\n"
        "  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);\n"
        "  p3 += dot(p3, p3.yzx + 33.33);\n"
        "  return fract((p3.x + p3.y) * p3.z);\n"
        "}\n"
        "float crt_sd_round_box(vec2 p, vec2 b, float r) {\n"
        "  vec2 q = abs(p) - b + r;\n"
        "  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n"
        "}\n"
        "vec3 crt_mask(vec2 frag) {\n"
        "  float w = max(1.0, floor(crt_mask_size + 0.5));\n"
        "  float dim = 1.0 - crt_mask_strength;\n"
        "  float x = frag.x;\n"
        "  float gap = 1.0;\n"
        "  if (crt_mask_type > 0.5 && crt_mask_type < 1.5) {\n"
        "    float row = floor(frag.y / (4.0 * w));\n"
        "    x += mod(row, 2.0) * 1.5 * w;\n"
        "    if (mod(frag.y, 4.0 * w) < w) gap = 1.0 - 0.5 * crt_mask_strength;\n"
        "  } else if (crt_mask_type > 1.5) {\n"
        "    x += floor(frag.y / w) * w;\n"
        "  }\n"
        "  float i = mod(floor(x / w), 3.0);\n"
        "  vec3 m = vec3(dim);\n"
        "  if (i < 0.5) m.r = 1.0; else if (i < 1.5) m.g = 1.0; else m.b = 1.0;\n"
        "  return m * gap;\n"
        "}\n"
        "vec3 crt_screen(vec2 frag, vec2 p, vec2 s) {\n"
        "  float conv = (0.35 + crt_tube * (0.3 + 1.1 * dot(p, p))) / crt_size.x;\n"
        "  vec3 col = crt_lin(vec3(crt_fetch(s + vec2(conv, 0.0)).r,\n"
        "                          crt_fetch(s).g,\n"
        "                          crt_fetch(s - vec2(conv, 0.0)).b));\n"
        "  if (crt_glow > 0.001) {\n"
        "    vec2 o = 4.0 / crt_size;\n"
        "    vec3 h = crt_lin(crt_fetch(s + vec2(o.x, 0.0))) + crt_lin(crt_fetch(s - vec2(o.x, 0.0)))\n"
        "           + crt_lin(crt_fetch(s + vec2(0.0, o.y))) + crt_lin(crt_fetch(s - vec2(0.0, o.y)))\n"
        "           + crt_lin(crt_fetch(s + o * 1.6)) + crt_lin(crt_fetch(s - o * 1.6))\n"
        "           + crt_lin(crt_fetch(s + vec2(o.x, -o.y) * 1.6)) + crt_lin(crt_fetch(s + vec2(-o.x, o.y) * 1.6));\n"
        "    h /= 8.0;\n"
        "    col += h * crt_glow * (0.25 + 0.6 * crt_luma(h));\n"
        "  }\n"
        "  if (crt_scanline_strength > 0.001) {\n"
        "    float l = clamp(crt_luma(col), 0.0, 1.0);\n"
        "    float lines = crt_size.y / max(crt_scanline_period, 1.0);\n"
        "    float f = fract(s.y * lines) - 0.5;\n"
        "    float sigma = mix(0.16, 0.4, sqrt(l));\n"
        "    float beam = exp(-(f * f) / (2.0 * sigma * sigma));\n"
        "    float scan = min(beam / (sigma * 2.5066), 1.8);\n"
        "    col *= mix(1.0, scan, crt_scanline_strength);\n"
        "  }\n"
        "  if (crt_mask_strength > 0.001)\n"
        "    col *= crt_mask(frag) / (1.0 - crt_mask_strength * 0.45);\n"
        "  if (crt_vignette > 0.001) {\n"
        "    vec2 vv = s * (1.0 - s);\n"
        "    col *= pow(clamp(vv.x * vv.y * 16.0, 0.0, 1.0), 0.35 * crt_vignette);\n"
        "  }\n"
        "  if (crt_noise > 0.001) {\n"
        "    col += (crt_hash(floor(frag) + fract(crt_time * 7.13) * 917.0) - 0.5) * crt_noise * 0.05;\n"
        "    col *= 1.0 - crt_noise * 0.06 * (0.5 + 0.5 * sin(s.y * 5.0 - crt_time * 1.4));\n"
        "    col *= 1.0 - crt_noise * 0.02 * crt_hash(vec2(floor(crt_time * 30.0), 3.7));\n"
        "  }\n"
        "  col = pow(max(col * crt_bright_boost, 0.0), vec3(1.0 / crt_gamma_out));\n"
        "  if (crt_tube > 0.5) {\n"
        "    vec2 hp = (p - vec2(-0.42, -0.58)) * vec2(1.1, 2.3);\n"
        "    float spec = exp(-dot(hp, hp) * 2.4) * 0.075;\n"
        "    float sheen = 0.025 * clamp(1.0 - length(p - vec2(0.55, 0.65)) * 1.4, 0.0, 1.0);\n"
        "    col += (spec + sheen) * vec3(0.9, 0.95, 1.0);\n"
        "  }\n"
        "  return col;\n"
        "}\n"
        "void main() {\n"
        "  vec2 frag = gl_FragCoord.xy;\n"
        "  vec2 p = vec2(screen_pos.x, -screen_pos.y);\n"
        "  vec2 q = p * (1.0 + crt_curvature * 0.14 * vec2(p.y * p.y, p.x * p.x));\n"
        "  vec2 s = q * 0.5 + 0.5;\n"
        "  vec2 half_px = crt_size * 0.5;\n"
        "  float min_half = min(half_px.x, half_px.y);\n"
        "  float radius = crt_tube > 0.5 ? min_half * (0.05 + 0.07 * crt_curvature) : 0.0;\n"
        "  float sd = crt_sd_round_box(q * half_px, half_px, radius);\n"
        "  float inside = 1.0 - smoothstep(-1.0, 1.0, sd);\n"
        "  vec3 screen = vec3(0.0);\n"
        "  if (inside > 0.0) {\n"
        "    screen = crt_screen(frag, p, s);\n"
        "    if (crt_tube > 0.5) {\n"
        "      screen *= mix(0.3, 1.0, smoothstep(0.0, min_half * 0.11, -sd));\n"
        "      float r = -sd / (min_half * 0.01);\n"
        "      screen += exp(-r * r) * 0.1 * clamp(0.6 - p.y * 0.6, 0.0, 1.0);\n"
        "    }\n"
        "  }\n"
        "  if (crt_tube < 0.5) {\n"
        "    gl_FragColor = vec4(screen * inside, 1.0);\n"
        "    return;\n"
        "  }\n"
        "  float d = max(sd, 0.0);\n"
        "  vec3 bezel = vec3(0.05, 0.048, 0.046) * (1.05 - 0.3 * clamp(p.y * 0.5 + 0.5, 0.0, 1.0));\n"
        "  vec3 spill = (crt_fetch(clamp(s, 0.02, 0.98)) + crt_fetch(s * 0.9 + 0.05)) * 0.5;\n"
        "  bezel += spill * 0.32 * exp(-d / (min_half * 0.03));\n"
        "  float lip = (d - min_half * 0.014) / (min_half * 0.006);\n"
        "  bezel += 0.06 * exp(-lip * lip) * clamp(0.8 - p.y * 0.4, 0.0, 1.0);\n"
        "  gl_FragColor = vec4(mix(bezel, screen, inside), 1.0);\n"
        "}\n";

    const char *extensions = sampler->shader.extensions
                           ? sampler->shader.extensions : "";

    const char *vertex_shader[] = {
        sampler->shader.version,
        VERTEX_SHADER_BODY,
    };
    const char *fragment_shader[] = {
        sampler->shader.version,
        extensions,
        sampler->shader.precision,
        sampler->shader.body,
        FRAGMENT_SHADER_BODY,
    };

    GLuint program_id =
        vlc_gl_BuildProgram(VLC_OBJECT(filter), vt,
                            ARRAY_SIZE(vertex_shader), vertex_shader,
                            ARRAY_SIZE(fragment_shader), fragment_shader);
    if (!program_id)
        goto error;

    vlc_gl_sampler_FetchLocations(sampler, program_id);

    sys->program_id = program_id;

    sys->loc_vertex_pos = vt->GetAttribLocation(program_id, "vertex_pos");
    assert(sys->loc_vertex_pos != -1);

    sys->loc_tex_coords_in = vt->GetAttribLocation(program_id, "tex_coords_in");

    sys->loc_size = vt->GetUniformLocation(program_id, "crt_size");
    sys->loc_time = vt->GetUniformLocation(program_id, "crt_time");
    sys->loc_tc_origin = vt->GetUniformLocation(program_id, "crt_tc_origin");
    sys->loc_tc_x = vt->GetUniformLocation(program_id, "crt_tc_x");
    sys->loc_tc_y = vt->GetUniformLocation(program_id, "crt_tc_y");

    for (int i = 0; i < CRT_PARAM_COUNT; ++i)
    {
        sys->loc_param[i] =
            vt->GetUniformLocation(program_id, crt_uniform_names[i]);
        if (sys->loc_param[i] == -1)
            msg_Warn(filter, "uniform %s not found", crt_uniform_names[i]);
    }

    vt->GenBuffers(1, &sys->vbo);

    static const struct vlc_gl_filter_ops ops = {
        .draw = Draw,
        .close = Close,
    };
    filter->ops = &ops;

    return VLC_SUCCESS;

error:
    free(sys);
    return VLC_EGENERIC;
}

#define CRT_GAMMA_IN_TEXT N_("CRT gamma input")
#define CRT_GAMMA_OUT_TEXT N_("CRT gamma output")
#define CRT_BRIGHT_BOOST_TEXT N_("CRT brightness boost")
#define CRT_SCANLINE_STRENGTH_TEXT N_("CRT scanline strength")
#define CRT_SCANLINE_PERIOD_TEXT N_("CRT scanline period (pixels)")
#define CRT_SCANLINE_BEAM_TEXT N_("CRT scanline beam sharpness")
#define CRT_MASK_STRENGTH_TEXT N_("CRT mask strength")
#define CRT_MASK_SIZE_TEXT N_("CRT mask size (pixels per stripe)")
#define CRT_CURVATURE_TEXT N_("CRT tube curvature (0=flat, 1=curved)")
#define CRT_GLOW_TEXT N_("CRT phosphor glow")
#define CRT_VIGNETTE_TEXT N_("CRT vignette")
#define CRT_NOISE_TEXT N_("CRT noise and interference")
#define CRT_TUBE_TEXT N_("CRT picture tube (glass, reflections and bezel)")
#define CRT_MASK_TYPE_TEXT N_("CRT mask type (0=aperture grille, 1=slot, 2=dots)")

vlc_module_begin()
    set_shortname(N_("CRT shader"))
    set_description(N_("CRT shader filter (scanlines, phosphor mask and picture tube)"))
    set_capability("opengl filter", 0)
    set_callback_opengl_filter(Open)
    add_shortcut("crt")

    add_float_with_range(CRT_CFG_PREFIX "gamma-in", 2.2, 0.1, 5.0,
                         CRT_GAMMA_IN_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "gamma-out", 2.2, 0.1, 5.0,
                         CRT_GAMMA_OUT_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "bright-boost", 1.2, 1.0, 2.0,
                         CRT_BRIGHT_BOOST_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "scanline-strength", 0.7, 0.0, 1.0,
                         CRT_SCANLINE_STRENGTH_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "scanline-period", 2.0, 1.0, 8.0,
                         CRT_SCANLINE_PERIOD_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "scanline-beam", 1.5, 0.5, 5.0,
                         CRT_SCANLINE_BEAM_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "mask-strength", 0.3, 0.0, 1.0,
                         CRT_MASK_STRENGTH_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "mask-size", 1.0, 1.0, 8.0,
                         CRT_MASK_SIZE_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "curvature", 0.0, 0.0, 1.0,
                         CRT_CURVATURE_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "glow", 0.3, 0.0, 1.0,
                         CRT_GLOW_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "vignette", 0.25, 0.0, 1.0,
                         CRT_VIGNETTE_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "noise", 0.0, 0.0, 1.0,
                         CRT_NOISE_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "tube", 0.0, 0.0, 1.0,
                         CRT_TUBE_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "mask-type", 0.0, 0.0, 2.0,
                         CRT_MASK_TYPE_TEXT, NULL)
vlc_module_end()
