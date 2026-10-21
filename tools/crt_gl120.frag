#version 120
uniform sampler2D Textures[1];
vec4 vlc_texture(vec2 coords) { return texture2D(Textures[0], coords); }
varying vec2 tex_coords;
uniform float crt_gamma_in;
uniform float crt_gamma_out;
uniform float crt_bright_boost;
uniform float crt_scanline_strength;
uniform float crt_scanline_period;
uniform float crt_scanline_beam;
uniform float crt_mask_strength;
uniform float crt_mask_size;
#define PI 3.141592653589
void main() {
  vec3 col = vlc_texture(tex_coords).rgb;

  /* gamma input: work in linear space */
  col = pow(col, vec3(crt_gamma_in));

  /* horizontal scanlines (fixed pitch in screen space) */
  float scan = 1.0 - pow(cos(gl_FragCoord.y * 2.0 * PI
                              / crt_scanline_period)
                          * 0.5 + 0.5, crt_scanline_beam)
                          * crt_scanline_strength;
  col *= vec3(scan);

  /* RGB aperture-grille mask (vertical stripes, R/G/B cycling) */
  float pitch = crt_mask_size * 3.0;
  float m = mod(gl_FragCoord.x, pitch);
  float mask = 1.0 - crt_mask_strength;
  vec3 mask_weight;
  if (m < crt_mask_size)            mask_weight = vec3(1.0, mask, mask);
  else if (m < 2.0 * crt_mask_size) mask_weight = vec3(mask, 1.0, mask);
  else                              mask_weight = vec3(mask, mask, 1.0);
  col *= mask_weight;

  /* gamma output + brightness boost */
  col = pow(col, vec3(1.0 / crt_gamma_out)) * crt_bright_boost;
  gl_FragColor = vec4(col, 1.0);
}
