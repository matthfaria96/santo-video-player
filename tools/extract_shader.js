const fs = require('fs');
const path = require('path');

// Prefer the patch copy in this repo; fall back to a VLC checkout next to it.
const candidates = [
  path.join(__dirname, '..', 'vlc-patches', 'filter_crt.c'),
  path.join(__dirname, '..', 'vlc', 'modules', 'video_output', 'opengl', 'filter_crt.c'),
];
const src = fs.readFileSync(candidates.find((p) => fs.existsSync(p)), 'utf8');

function extract(name) {
  const re = new RegExp(name + '\\s*=\\s*((?:"(?:[^"\\\\]|\\\\.)*"\\s*)+);', 's');
  const m = re.exec(src);
  if (!m) throw new Error('not found: ' + name);
  const block = m[1];
  const lit = /"((?:[^"\\]|\\.)*)"/g;
  let out = '';
  let x;
  while ((x = lit.exec(block)) !== null) {
    out += x[1].replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  }
  return out;
}

const frag = extract('FRAGMENT_SHADER_BODY');
const vert = extract('VERTEX_SHADER_BODY');

const headerES = `#version 100
precision highp float;
precision highp sampler2D;
uniform sampler2D Textures[1];
vec4 vlc_texture(vec2 coords) { return texture2D(Textures[0], coords); }
`;

const headerGL = `#version 120
uniform sampler2D Textures[1];
vec4 vlc_texture(vec2 coords) { return texture2D(Textures[0], coords); }
`;

fs.writeFileSync(path.join(__dirname, 'crt_es100.frag'), headerES + frag);
fs.writeFileSync(path.join(__dirname, 'crt_gl120.frag'), headerGL + frag);
fs.writeFileSync(path.join(__dirname, 'crt_es100.vert'), '#version 100\n' + vert);

console.log('fragment length:', frag.length);
console.log('vertex length:', vert.length);
console.log('--- fragment head ---');
console.log(frag.slice(0, 500));
