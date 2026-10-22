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
    CRT_CURVATURE,
    CRT_PARAM_COUNT,
};

static const char *const crt_option_names[CRT_PARAM_COUNT + 1] = {
    "gamma-in", "gamma-out", "bright-boost",
    "scanline-strength", "scanline-period", "scanline-beam",
    "mask-strength", "mask-size", "curvature",
    NULL,
};

static const char *const crt_uniform_names[CRT_PARAM_COUNT] = {
    "crt_gamma_in", "crt_gamma_out", "crt_bright_boost",
    "crt_scanline_strength", "crt_scanline_period", "crt_scanline_beam",
    "crt_mask_strength", "crt_mask_size", "crt_curvature",
};

struct sys {
    struct vlc_gl_api api;
    struct vlc_gl_sampler *sampler;

    GLuint program_id;
    GLuint vbo;

    GLint loc_vertex_pos;
    GLint loc_tex_coords_in;
    GLint loc_param[CRT_PARAM_COUNT];

    float params[CRT_PARAM_COUNT];
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
    }

    const GLsizei stride = 4 * sizeof(float);

    vt->EnableVertexAttribArray(sys->loc_vertex_pos);
    vt->VertexAttribPointer(sys->loc_vertex_pos, 2, GL_FLOAT, GL_FALSE, stride,
                            (const void *) 0);

    intptr_t offset = 2 * sizeof(float);
    vt->EnableVertexAttribArray(sys->loc_tex_coords_in);
    vt->VertexAttribPointer(sys->loc_tex_coords_in, 2, GL_FLOAT, GL_FALSE,
                            stride, (const void *) offset);

    for (int i = 0; i < CRT_PARAM_COUNT; ++i)
        if (sys->loc_param[i] != -1)
            vt->Uniform1f(sys->loc_param[i], sys->params[i]);

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
    (void) size_out;

    struct sys *sys = filter->sys = malloc(sizeof(*sys));
    if (!sys)
        return VLC_EGENERIC;

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
        "varying vec2 tex_coords;\n"
        "void main() {\n"
        "  gl_Position = vec4(vertex_pos, 0.0, 1.0);\n"
        "  tex_coords = tex_coords_in;\n"
        "}\n";

    /* CRT effect (adapted from crt-easymode): scanlines, RGB aperture-grille
     * mask and gamma, all computed in screen space so they are visible at any
     * resolution. Operates only on the video texture. */
    static const char *const FRAGMENT_SHADER_BODY =
        "varying vec2 tex_coords;\n"
        "uniform float crt_gamma_in;\n"
        "uniform float crt_gamma_out;\n"
        "uniform float crt_bright_boost;\n"
        "uniform float crt_scanline_strength;\n"
        "uniform float crt_scanline_period;\n"
        "uniform float crt_scanline_beam;\n"
        "uniform float crt_mask_strength;\n"
        "uniform float crt_mask_size;\n"
        "uniform float crt_curvature;\n"
        "#define PI 3.141592653589\n"
        "void main() {\n"
        "  vec2 uv = tex_coords;\n"
        "  if (crt_curvature > 0.001) {\n"
        "    vec2 p = uv * 2.0 - 1.0;\n"
        "    p *= 1.0 + crt_curvature * 0.35 * dot(p, p);\n"
        "    uv = p * 0.5 + 0.5;\n"
        "    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {\n"
        "      gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);\n"
        "      return;\n"
        "    }\n"
        "  }\n"
        "  vec3 col = vlc_texture(uv).rgb;\n"
        "\n"
        "  /* gamma input: work in linear space */\n"
        "  col = pow(col, vec3(crt_gamma_in));\n"
        "\n"
        "  /* horizontal scanlines (fixed pitch in screen space) */\n"
        "  float scan = 1.0 - pow(cos(gl_FragCoord.y * 2.0 * PI\n"
        "                              / crt_scanline_period)\n"
        "                          * 0.5 + 0.5, crt_scanline_beam)\n"
        "                          * crt_scanline_strength;\n"
        "  col *= vec3(scan);\n"
        "\n"
        "  /* RGB aperture-grille mask (vertical stripes, R/G/B cycling) */\n"
        "  float pitch = crt_mask_size * 3.0;\n"
        "  float m = mod(gl_FragCoord.x, pitch);\n"
        "  float mask = 1.0 - crt_mask_strength;\n"
        "  vec3 mask_weight;\n"
        "  if (m < crt_mask_size)            mask_weight = vec3(1.0, mask, mask);\n"
        "  else if (m < 2.0 * crt_mask_size) mask_weight = vec3(mask, 1.0, mask);\n"
        "  else                              mask_weight = vec3(mask, mask, 1.0);\n"
        "  col *= mask_weight;\n"
        "\n"
        "  /* gamma output + brightness boost */\n"
        "  col = pow(col, vec3(1.0 / crt_gamma_out)) * crt_bright_boost;\n"
        "  gl_FragColor = vec4(col, 1.0);\n"
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
    assert(sys->loc_tex_coords_in != -1);

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

vlc_module_begin()
    set_shortname(N_("CRT shader"))
    set_description(N_("CRT shader filter (scanlines and RGB mask)"))
    set_capability("opengl filter", 0)
    set_callback_opengl_filter(Open)
    add_shortcut("crt")

    add_float_with_range(CRT_CFG_PREFIX "gamma-in", 2.0, 0.1, 5.0,
                         CRT_GAMMA_IN_TEXT, NULL)
    add_float_with_range(CRT_CFG_PREFIX "gamma-out", 1.8, 0.1, 5.0,
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
vlc_module_end()
