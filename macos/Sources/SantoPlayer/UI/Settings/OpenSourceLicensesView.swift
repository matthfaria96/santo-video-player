import SwiftUI

/// Copyright notices of the bundled open-source software, as their licenses require.
struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let license: String
        let text: String
    }

    private let entries = [
        Entry(id: "santo", name: "Santo Video Player", license: "GNU General Public License v2.0 or later", text: """
        Copyright (C) 2024–2026 Matheus Faria
        Source code: https://github.com/matthfaria96/santo-video-player

        This program is free software; you can redistribute it and/or modify it under the \
        terms of the GNU General Public License as published by the Free Software Foundation; \
        either version 2 of the License, or (at your option) any later version. It is \
        distributed WITHOUT ANY WARRANTY; without even the implied warranty of \
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

        Full license text: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
        """),
        Entry(id: "mpv", name: "mpv / libmpv", license: "GNU LGPL v2.1 or later", text: """
        Copyright (C) mpv contributors. https://mpv.io
        Source code: https://github.com/mpv-player/mpv
        Full license text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
        """),
        Entry(id: "ffmpeg", name: "FFmpeg", license: "GNU LGPL v2.1 or later", text: """
        Copyright (C) the FFmpeg developers. https://ffmpeg.org
        Source code: https://git.ffmpeg.org/ffmpeg.git
        Full license text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
        """),
        Entry(id: "mpvkit", name: "MPVKit", license: "GNU LGPL v3.0", text: """
        Copyright (C) MPVKit contributors.
        Source code: https://github.com/mpvkit/MPVKit
        Full license text: https://www.gnu.org/licenses/lgpl-3.0.html
        """),
        Entry(id: "libass", name: "libass", license: "ISC License", text: """
        Copyright (C) 2006 Evgeniy Stepanov and libass contributors.
        Permission to use, copy, modify, and distribute this software for any purpose with or \
        without fee is hereby granted, provided that the above copyright notice and this \
        permission notice appear in all copies. THE SOFTWARE IS PROVIDED "AS IS".
        """),
        Entry(id: "dav1d", name: "dav1d", license: "BSD 2-Clause License", text: """
        Copyright (C) 2018–2026, VideoLAN and dav1d authors. All rights reserved.
        Redistribution and use in source and binary forms, with or without modification, are \
        permitted provided that the copyright notice, this list of conditions and the \
        disclaimer are retained. THIS SOFTWARE IS PROVIDED "AS IS".
        """),
        Entry(id: "libplacebo", name: "libplacebo", license: "GNU LGPL v2.1 or later", text: """
        Copyright (C) libplacebo contributors. https://code.videolan.org/videolan/libplacebo
        """),
        Entry(id: "freetype", name: "FreeType · HarfBuzz · FriBidi", license: "FTL · MIT · LGPL v2.1", text: """
        Portions of this software are copyright (C) The FreeType Project (www.freetype.org). \
        HarfBuzz: copyright (C) HarfBuzz contributors, MIT License. \
        GNU FriBidi: copyright (C) FriBidi contributors, LGPL v2.1 or later.
        """),
        Entry(id: "crt", name: "crt-easymode", license: "GNU GPL", text: """
        CRT Shader by EasyMode (libretro/slang-shaders). The CRT effect is derived from it.
        https://github.com/libretro/slang-shaders
        """),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Licenças de código aberto").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("O Santo Video Player é feito sobre os projetos de código aberto abaixo. Os avisos de copyright e as licenças ficam aqui, como essas licenças exigem.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.name).font(.headline)
                                Text(entry.license).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                            }
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 560)
    }
}
