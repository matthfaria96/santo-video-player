#version 100
attribute vec2 vertex_pos;
attribute vec2 tex_coords_in;
varying vec2 screen_pos;
void main() {
  gl_Position = vec4(vertex_pos, 0.0, 1.0);
  screen_pos = vertex_pos;
}
