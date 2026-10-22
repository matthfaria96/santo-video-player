#!/usr/bin/env python3
"""Lists the localizable keys in Sources/ (Portuguese is the development
language) as Localizable.strings expects them. Interpolations become %@
(text) or %lld (integers), matching String(localized:) and SwiftUI."""
import pathlib, re, sys

CALLS = re.compile(r'(?:String\(localized: |Text\(|Button\(|Toggle\(|Label\(|Menu\(|CommandMenu\('
                   r'|\.help\(|\.accessibilityLabel\(|Window\(|EffectSlider\(title: |row\('
                   r'|SettingsRow\(title: |SettingsSection\(title: |detail: |footer: |Picker\()"')
INT_HINTS = ('count', 'Int(', 'index', '* 100')


def read_literal(src: str, i: int):
    """Reads the Swift literal whose opening quote is at i; returns (key, end)."""
    out, i = '', i + 1
    while src[i] != '"':
        if src.startswith('\\(', i):
            depth, j = 1, i + 2
            while depth:
                if src[j] == '"':                      # nested literal inside \( )
                    _, j = read_literal(src, j)
                    continue
                depth += {'(': 1, ')': -1}.get(src[j], 0)
                j += 1
            expr = src[i + 2:j - 1]
            out += '%lld' if any(h in expr for h in INT_HINTS) else '%@'
            i = j
        elif src[i] == '\\':
            out += src[i:i + 2]
            i += 2
        else:
            out += '%%' if src[i] == '%' else src[i]   # Swift escapes literal %
            i += 1
    return out, i + 1


keys = []
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'Sources')
for path in sorted(root.rglob('*.swift')):
    src = path.read_text()
    for match in CALLS.finditer(src):
        key, _ = read_literal(src, match.end() - 1)
        if re.search(r'[A-Za-zÀ-ú]{2}', key) and key not in keys:
            keys.append(key)
print('\n'.join(keys))
