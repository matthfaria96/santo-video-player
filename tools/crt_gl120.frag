#version 120
uniform sampler2D Textures[1];
vec4 vlc_texture(vec2 coords) { return texture2D(Textures[0], coords); }
varying vec2 screen_pos;
uniform float crt_gamma_in;
uniform float crt_gamma_out;
uniform float crt_bright_boost;
uniform float crt_scanline_strength;
uniform float crt_scanline_period;
uniform float crt_scanline_beam;
uniform float crt_mask_strength;
uniform float crt_mask_size;
uniform float crt_curvature;
uniform float crt_glow;
uniform float crt_vignette;
uniform float crt_noise;
uniform float crt_tube;
uniform float crt_mask_type;
uniform vec2 crt_size;
uniform float crt_time;
uniform vec2 crt_tc_origin;
uniform vec2 crt_tc_x;
uniform vec2 crt_tc_y;

vec3 crt_fetch(vec2 s) {
  s = clamp(s, 0.0, 1.0);
  /* s: 0..1 with y = 0 at the top */
  return vlc_texture(crt_tc_origin + s.x * crt_tc_x + (1.0 - s.y) * crt_tc_y).rgb;
}
vec3 crt_lin(vec3 c) { return pow(max(c, 0.0), vec3(crt_gamma_in)); }
float crt_luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float crt_hash(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
float crt_sd_round_box(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
vec3 crt_mask(vec2 frag) {
  float w = max(1.0, floor(crt_mask_size + 0.5));
  float dim = 1.0 - crt_mask_strength;
  float x = frag.x;
  float gap = 1.0;
  if (crt_mask_type > 0.5 && crt_mask_type < 1.5) {
    float row = floor(frag.y / (4.0 * w));
    x += mod(row, 2.0) * 1.5 * w;
    if (mod(frag.y, 4.0 * w) < w) gap = 1.0 - 0.5 * crt_mask_strength;
  } else if (crt_mask_type > 1.5) {
    x += floor(frag.y / w) * w;
  }
  float i = mod(floor(x / w), 3.0);
  vec3 m = vec3(dim);
  if (i < 0.5) m.r = 1.0; else if (i < 1.5) m.g = 1.0; else m.b = 1.0;
  return m * gap;
}
vec3 crt_screen(vec2 frag, vec2 p, vec2 s) {
  float conv = (0.35 + crt_tube * (0.3 + 1.1 * dot(p, p))) / crt_size.x;
  vec3 col = crt_lin(vec3(crt_fetch(s + vec2(conv, 0.0)).r,
                          crt_fetch(s).g,
                          crt_fetch(s - vec2(conv, 0.0)).b));
  if (crt_glow > 0.001) {
    vec2 o = 4.0 / crt_size;
    vec3 h = crt_lin(crt_fetch(s + vec2(o.x, 0.0))) + crt_lin(crt_fetch(s - vec2(o.x, 0.0)))
           + crt_lin(crt_fetch(s + vec2(0.0, o.y))) + crt_lin(crt_fetch(s - vec2(0.0, o.y)))
           + crt_lin(crt_fetch(s + o * 1.6)) + crt_lin(crt_fetch(s - o * 1.6))
           + crt_lin(crt_fetch(s + vec2(o.x, -o.y) * 1.6)) + crt_lin(crt_fetch(s + vec2(-o.x, o.y) * 1.6));
    h /= 8.0;
    col += h * crt_glow * (0.25 + 0.6 * crt_luma(h));
  }
  if (crt_scanline_strength > 0.001) {
    float l = clamp(crt_luma(col), 0.0, 1.0);
    float lines = crt_size.y / max(crt_scanline_period, 1.0);
    float f = fract(s.y * lines) - 0.5;
    float sigma = mix(0.16, 0.4, sqrt(l));
    float beam = exp(-(f * f) / (2.0 * sigma * sigma));
    float scan = min(beam / (sigma * 2.5066), 1.8);
    col *= mix(1.0, scan, crt_scanline_strength);
  }
  if (crt_mask_strength > 0.001)
    col *= crt_mask(frag) / (1.0 - crt_mask_strength * 0.45);
  if (crt_vignette > 0.001) {
    vec2 vv = s * (1.0 - s);
    col *= pow(clamp(vv.x * vv.y * 16.0, 0.0, 1.0), 0.35 * crt_vignette);
  }
  if (crt_noise > 0.001) {
    col += (crt_hash(floor(frag) + fract(crt_time * 7.13) * 917.0) - 0.5) * crt_noise * 0.05;
    col *= 1.0 - crt_noise * 0.06 * (0.5 + 0.5 * sin(s.y * 5.0 - crt_time * 1.4));
    col *= 1.0 - crt_noise * 0.02 * crt_hash(vec2(floor(crt_time * 30.0), 3.7));
  }
  col = pow(max(col * crt_bright_boost, 0.0), vec3(1.0 / crt_gamma_out));
  if (crt_tube > 0.5) {
    vec2 hp = (p - vec2(-0.42, -0.58)) * vec2(1.1, 2.3);
    float spec = exp(-dot(hp, hp) * 2.4) * 0.075;
    float sheen = 0.025 * clamp(1.0 - length(p - vec2(0.55, 0.65)) * 1.4, 0.0, 1.0);
    col += (spec + sheen) * vec3(0.9, 0.95, 1.0);
  }
  return col;
}
void main() {
  vec2 frag = gl_FragCoord.xy;
  vec2 p = vec2(screen_pos.x, -screen_pos.y);
  vec2 q = p * (1.0 + crt_curvature * 0.14 * vec2(p.y * p.y, p.x * p.x));
  vec2 s = q * 0.5 + 0.5;
  vec2 half_px = crt_size * 0.5;
  float min_half = min(half_px.x, half_px.y);
  float radius = crt_tube > 0.5 ? min_half * (0.05 + 0.07 * crt_curvature) : 0.0;
  float sd = crt_sd_round_box(q * half_px, half_px, radius);
  float inside = 1.0 - smoothstep(-1.0, 1.0, sd);
  vec3 screen = vec3(0.0);
  if (inside > 0.0) {
    screen = crt_screen(frag, p, s);
    if (crt_tube > 0.5) {
      screen *= mix(0.3, 1.0, smoothstep(0.0, min_half * 0.11, -sd));
      float r = -sd / (min_half * 0.01);
      screen += exp(-r * r) * 0.1 * clamp(0.6 - p.y * 0.6, 0.0, 1.0);
    }
  }
  if (crt_tube < 0.5) {
    gl_FragColor = vec4(screen * inside, 1.0);
    return;
  }
  float d = max(sd, 0.0);
  vec3 bezel = vec3(0.05, 0.048, 0.046) * (1.05 - 0.3 * clamp(p.y * 0.5 + 0.5, 0.0, 1.0));
  vec3 spill = (crt_fetch(clamp(s, 0.02, 0.98)) + crt_fetch(s * 0.9 + 0.05)) * 0.5;
  bezel += spill * 0.32 * exp(-d / (min_half * 0.03));
  float lip = (d - min_half * 0.014) / (min_half * 0.006);
  bezel += 0.06 * exp(-lip * lip) * clamp(0.8 - p.y * 0.4, 0.0, 1.0);
  gl_FragColor = vec4(mix(bezel, screen, inside), 1.0);
}
