// Santo Video Player — GUI funcional sobre libvlc + shader CRT
//
// Player nativo (Win32 + libvlc) com tema escuro e controles completos:
//   - abrir / arrastar-e-soltar (um ou vários arquivos → playlist)
//   - reproduzir / pausar / parar / anterior / próxima
//   - barra de progresso (seek) + tempo atual/total + velocidade
//   - volume + mudo
//   - tela cheia (F, F11, Esc, duplo clique) com auto-ocultar
//   - painel "Efeitos CRT" com presets + sliders
//   - legendas automáticas (.srt/.sub/.ass com o mesmo nome)
//   - persistência de janela/volume/preset (SantoVideoPlayer.ini)
//   - atalhos de teclado
//
// Build: ver build-gui.ps1
// Licença: GPL-2.0+ (usa o libvlc do VLC).

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <windowsx.h>
#include <commdlg.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <cstdio>
#include <cstdint>

#include <vlc/vlc.h>

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------
static constexpr int  kBarH        = 78;
static constexpr bool kCrtEnabled  = true;
static constexpr UINT_PTR kTimerId      = 1;
static constexpr UINT_PTR kClickTimerId = 2;
static constexpr UINT kTimerMs          = 250;

static const COLORREF kBg      = RGB(0x15, 0x15, 0x15);
static const COLORREF kBarBg   = RGB(0x20, 0x20, 0x20);
static const COLORREF kBtnBg   = RGB(0x2b, 0x2b, 0x2b);
static const COLORREF kBtnHov  = RGB(0x3c, 0x3c, 0x3c);
static const COLORREF kAccent  = RGB(0xff, 0x88, 0x00);
static const COLORREF kText    = RGB(0xea, 0xea, 0xea);
static const COLORREF kTextDim = RGB(0x9a, 0x9a, 0x9a);
static const COLORREF kTrack   = RGB(0x40, 0x40, 0x40);
static const COLORREF kPanelBg = RGB(0x1c, 0x1c, 0x1c);

static const wchar_t kGlyphOpen[]    = L"\uE8E5";
static const wchar_t kGlyphPrev[]    = L"\uE892";
static const wchar_t kGlyphPlay[]    = L"\uE768";
static const wchar_t kGlyphPause[]   = L"\uE769";
static const wchar_t kGlyphStop[]    = L"\uE71A";
static const wchar_t kGlyphNext[]    = L"\uE893";
static const wchar_t kGlyphVol[]     = L"\uE767";
static const wchar_t kGlyphMute[]    = L"\uE74F";
static const wchar_t kGlyphFull[]    = L"\uE740";
static const wchar_t kGlyphRestore[] = L"\uE73F";
static const wchar_t kGlyphFx[]      = L"\uE790";

// ---------------------------------------------------------------------------
// Config de shader + presets
// ---------------------------------------------------------------------------
struct ShaderConfig {
    bool   enabled = true;
    double scanline_strength = 0.7;
    double mask_strength     = 0.3;
    double scanline_period   = 2.0;
    double gamma_in          = 2.0;
    double gamma_out         = 1.8;
    double bright_boost      = 1.2;
    double curvature         = 0.0;
};

struct Preset {
    const wchar_t* name;
    bool   enabled;
    double scanline;
    double mask;
    double period;
    double curvature;
};
static const Preset kPresets[] = {
    { L"Sem shader",             false, 0.0, 0.0, 2.0, 0.0 },
    { L"CRT Clássico (padrão)",  true,  0.7, 0.3, 2.0, 0.0 },
    { L"CRT Suave",              true,  0.4, 0.2, 2.0, 0.0 },
    { L"CRT Forte",              true,  0.9, 0.6, 3.0, 0.0 },
    { L"Só scanlines",           true,  0.7, 0.0, 2.0, 0.0 },
    { L"CRT Tubo (curvo)",       true,  0.7, 0.3, 2.0, 1.0 },
};
static const int kPresetCount = 6;

// ---------------------------------------------------------------------------
// Estado global
// ---------------------------------------------------------------------------
enum Btn { B_OPEN, B_PREV, B_PLAY, B_STOP, B_NEXT, B_MUTE, B_FX, B_FULL, B_COUNT };

struct App {
    HWND hMain  = nullptr;
    HWND hVideo = nullptr;
    HWND hFx    = nullptr;
    HWND hOsd   = nullptr;

    HFONT uiFont    = nullptr;
    HFONT iconFont  = nullptr;
    HFONT hintFont  = nullptr;
    HFONT titleFont = nullptr;

    libvlc_instance_t*     inst  = nullptr;
    libvlc_media_t*        media = nullptr;
    libvlc_media_player_t* mp    = nullptr;

    std::wstring file;
    std::wstring lastDir;
    std::wstring osdText;
    DWORD osdUntil = 0;
    std::vector<std::wstring> playlist;
    int playIndex = -1;
    int loopMode = 0;      // 0 off, 1 uma, 2 todas
    int aspectIdx = 0;
    bool pendingClick = false;
    bool hasVideo = true;
    DWORD noVoutSince = 0;

    bool playing         = false;
    bool fullscreen      = false;
    bool controlsVisible = true;
    bool seekDrag        = false;
    bool volDrag         = false;
    bool fxOpen          = false;
    bool fxDragScan      = false;
    bool fxDragMask      = false;

    int  volume = 100;
    bool muted  = false;
    float rate  = 1.0f;

    libvlc_time_t curTime = 0;
    libvlc_time_t length  = 0;
    double seekPos = 0.0;

    RECT rcVideo{}, rcBar{}, rcSeek{}, rcVol{}, btn[B_COUNT]{};
    int  hover = -1;
    bool tracking = false;
    DWORD lastMouseMove = 0;
    WINDOWPLACEMENT wp{};

    ShaderConfig cfg;
    int  presetIndex = 1;
    libvlc_time_t pendingSeek = -1;
    RECT initialRect{};
    bool hasInitialRect = false;
};
static App g;

static void layout();
static void showOsd(const std::wstring& text);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static std::string w2a(const std::wstring& w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string s((size_t)n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
    if (!s.empty() && s.back() == '\0') s.pop_back();
    return s;
}

static double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

static std::wstring fmtTime(libvlc_time_t us) {
    if (us < 0) us = 0;
    long long s = us / 1000000;
    int h = (int)(s / 3600), m = (int)((s % 3600) / 60), sec = (int)(s % 60);
    wchar_t buf[32];
    if (h > 0) swprintf(buf, 32, L"%d:%02d:%02d", h, m, sec);
    else       swprintf(buf, 32, L"%d:%02d", m, sec);
    return buf;
}

static std::wstring fmtRate(float r) {
    wchar_t buf[16];
    swprintf(buf, 16, L"%.2f", r);
    std::wstring s = buf;
    while (!s.empty() && s.back() == L'0') s.pop_back();
    if (!s.empty() && s.back() == L'.') s.pop_back();
    return s + L"x";
}

static void msgBox(const wchar_t* text) {
    MessageBoxW(g.hMain, text, L"Santo Video Player", MB_ICONINFORMATION);
}

static void applyDarkTitlebar(HWND h) {
    HMODULE d = LoadLibraryW(L"dwmapi.dll");
    if (!d) return;
    typedef HRESULT (WINAPI *Fn)(HWND, DWORD, LPCVOID, DWORD);
    Fn fn = (Fn)GetProcAddress(d, "DwmSetWindowAttribute");
    if (fn) {
        BOOL on = TRUE;
        fn(h, 20, &on, sizeof(on));
        fn(h, 19, &on, sizeof(on));
    }
    FreeLibrary(d);
}

static std::wstring settingsPath() {
    wchar_t buf[MAX_PATH];
    GetModuleFileNameW(nullptr, buf, MAX_PATH);
    std::wstring p = buf;
    size_t slash = p.find_last_of(L"\\/");
    if (slash != std::wstring::npos) p = p.substr(0, slash + 1);
    return p + L"SantoVideoPlayer.ini";
}

static void loadSettings() {
    std::wstring ini = settingsPath();
    int x = GetPrivateProfileIntW(L"window", L"x", INT_MIN, ini.c_str());
    int y = GetPrivateProfileIntW(L"window", L"y", INT_MIN, ini.c_str());
    int w = GetPrivateProfileIntW(L"window", L"w", 0, ini.c_str());
    int h = GetPrivateProfileIntW(L"window", L"h", 0, ini.c_str());
    if (x != INT_MIN && y != INT_MIN && w >= 480 && h >= 320) {
        g.initialRect = { x, y, x + w, y + h };
        g.hasInitialRect = true;
    }
    g.volume = clampi((int)GetPrivateProfileIntW(L"player", L"volume", 100, ini.c_str()), 0, 100);
    g.muted  = GetPrivateProfileIntW(L"player", L"mute", 0, ini.c_str()) != 0;
    g.presetIndex = clampi((int)GetPrivateProfileIntW(L"player", L"preset", 1, ini.c_str()), 0, kPresetCount - 1);
    wchar_t dir[MAX_PATH] = {0};
    GetPrivateProfileStringW(L"player", L"lastdir", L"", dir, MAX_PATH, ini.c_str());
    g.lastDir = dir;
    g.loopMode = clampi((int)GetPrivateProfileIntW(L"player", L"loop", 0, ini.c_str()), 0, 2);
    const Preset& p = kPresets[g.presetIndex];
    g.cfg.enabled = p.enabled;
    g.cfg.scanline_strength = p.scanline;
    g.cfg.mask_strength = p.mask;
    g.cfg.scanline_period = p.period;
    g.cfg.curvature = p.curvature;
}

static void saveSettings() {
    std::wstring ini = settingsPath();
    RECT rc;
    if (g.fullscreen) rc = g.wp.rcNormalPosition;
    else GetWindowRect(g.hMain, &rc);

    wchar_t buf[32];
    swprintf(buf, 32, L"%d", rc.left);   WritePrivateProfileStringW(L"window", L"x", buf, ini.c_str());
    swprintf(buf, 32, L"%d", rc.top);    WritePrivateProfileStringW(L"window", L"y", buf, ini.c_str());
    swprintf(buf, 32, L"%d", rc.right - rc.left); WritePrivateProfileStringW(L"window", L"w", buf, ini.c_str());
    swprintf(buf, 32, L"%d", rc.bottom - rc.top); WritePrivateProfileStringW(L"window", L"h", buf, ini.c_str());
    swprintf(buf, 32, L"%d", g.volume);  WritePrivateProfileStringW(L"player", L"volume", buf, ini.c_str());
    swprintf(buf, 32, L"%d", g.muted ? 1 : 0); WritePrivateProfileStringW(L"player", L"mute", buf, ini.c_str());
    swprintf(buf, 32, L"%d", g.presetIndex); WritePrivateProfileStringW(L"player", L"preset", buf, ini.c_str());
    swprintf(buf, 32, L"%d", g.loopMode);    WritePrivateProfileStringW(L"player", L"loop", buf, ini.c_str());
    if (!g.file.empty()) {
        std::wstring folder = g.file;
        size_t s = folder.find_last_of(L"\\/");
        if (s != std::wstring::npos) folder = folder.substr(0, s + 1);
        WritePrivateProfileStringW(L"player", L"lastdir", folder.c_str(), ini.c_str());
    }
}

// ---------------------------------------------------------------------------
// libvlc
// ---------------------------------------------------------------------------
static std::vector<const char*> buildVlcArgs(std::vector<std::string>& store) {
    store.clear();
    store.push_back("santo-video-player");
    store.push_back("--no-video-title-show");
    store.push_back("--no-snapshot-preview");
    if (kCrtEnabled && g.cfg.enabled) {
        store.push_back("--vout=gl");
        store.push_back("--gl-crt");
        char buf[64];
        std::snprintf(buf, sizeof buf, "--crt-scanline-strength=%.2f", g.cfg.scanline_strength);
        store.push_back(buf);
        std::snprintf(buf, sizeof buf, "--crt-mask-strength=%.2f", g.cfg.mask_strength);
        store.push_back(buf);
        std::snprintf(buf, sizeof buf, "--crt-scanline-period=%.2f", g.cfg.scanline_period);
        store.push_back(buf);
        std::snprintf(buf, sizeof buf, "--crt-gamma-in=%.2f", g.cfg.gamma_in);
        store.push_back(buf);
        std::snprintf(buf, sizeof buf, "--crt-gamma-out=%.2f", g.cfg.gamma_out);
        store.push_back(buf);
        std::snprintf(buf, sizeof buf, "--crt-bright-boost=%.2f", g.cfg.bright_boost);
        store.push_back(buf);
        std::snprintf(buf, sizeof buf, "--crt-curvature=%.2f", g.cfg.curvature);
        store.push_back(buf);
    }
    std::vector<const char*> args;
    args.reserve(store.size());
    for (auto& s : store) args.push_back(s.c_str());
    return args;
}

static void ensureInstance() {
    if (g.inst) return;
    std::vector<std::string> store;
    auto args = buildVlcArgs(store);
    g.inst = libvlc_new((int)args.size(), (const char* const*)args.data());
    if (!g.inst) msgBox(L"Não foi possível iniciar o libvlc.");
}

static void closePlayer() {
    if (g.mp)    { libvlc_media_player_stop_async(g.mp); libvlc_media_player_release(g.mp); g.mp = nullptr; }
    if (g.media) { libvlc_media_release(g.media); g.media = nullptr; }
    g.playing = false;
}

static std::wstring baseName(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) dot = path.size();
    return path.substr(0, dot);
}

static std::string pathToFileUri(const std::wstring& path) {
    std::string p = w2a(path);
    std::string uri = "file:///";
    for (char c : p) {
        if (c == '\\') uri += '/';
        else if (c == ' ') uri += "%20";
        else uri += c;
    }
    return uri;
}

static void loadSubtitles(const std::wstring& path) {
    if (!g.mp) return;
    static const wchar_t* exts[] = { L".srt", L".sub", L".ass", L".ssa", L".vtt" };
    std::wstring base = baseName(path);
    for (auto e : exts) {
        std::wstring sub = base + e;
        if (GetFileAttributesW(sub.c_str()) != INVALID_FILE_ATTRIBUTES) {
            std::string uri = pathToFileUri(sub);
            libvlc_media_player_add_slave(g.mp, libvlc_media_slave_type_subtitle, uri.c_str(), true);
            break;
        }
    }
}

static void startPlayback(const std::wstring& path) {
    std::string p = w2a(path);
    g.media = libvlc_media_new_path(p.c_str());
    if (!g.media) { msgBox(L"Não foi possível abrir o arquivo."); return; }

    g.mp = libvlc_media_player_new_from_media(g.inst, g.media, nullptr, nullptr);
    if (!g.mp) { msgBox(L"Não foi possível criar o player."); return; }

    libvlc_media_player_set_hwnd(g.mp, g.hVideo);
    libvlc_audio_set_volume(g.mp, g.volume);
    libvlc_audio_set_mute(g.mp, g.muted ? 1 : 0);
    if (g.rate != 1.0f) libvlc_media_player_set_rate(g.mp, g.rate);
    loadSubtitles(path);
    libvlc_media_player_play(g.mp);
    g.playing = true;
    g.hasVideo = true;
    g.noVoutSince = 0;
    g.curTime = 0; g.length = 0; g.seekPos = 0.0;
}

static void updateTitle() {
    const wchar_t* base = wcsrchr(g.file.c_str(), L'\\');
    std::wstring name = base ? (base + 1) : g.file.c_str();
    std::wstring t = L"Santo Video Player — " + name;
    if (g.playlist.size() > 1)
        t += L"  (" + std::to_wstring(g.playIndex + 1) + L"/" + std::to_wstring(g.playlist.size()) + L")";
    SetWindowTextW(g.hMain, t.c_str());
}

static void playOne(const std::wstring& path) {
    closePlayer();
    ensureInstance();
    if (!g.inst) return;
    g.file = path;
    g.aspectIdx = 0;   // proporção volta ao padrão ao abrir arquivo novo
    startPlayback(path);
    updateTitle();
    const wchar_t* base = wcsrchr(path.c_str(), L'\\');
    showOsd(base ? (base + 1) : path.c_str());
    InvalidateRect(g.hMain, nullptr, FALSE);
}

static void openPath(const std::wstring& path) {
    g.playlist.clear();
    g.playlist.push_back(path);
    g.playIndex = 0;
    playOne(path);
}

static void openFiles(const std::vector<std::wstring>& files) {
    g.playlist = files;
    g.playIndex = 0;
    if (!files.empty()) playOne(files[0]);
}

static void playAt(int i) {
    if (i < 0 || i >= (int)g.playlist.size()) return;
    g.playIndex = i;
    playOne(g.playlist[i]);
}

static void nextTrack() {
    if (g.playIndex + 1 < (int)g.playlist.size()) playAt(g.playIndex + 1);
}

static void prevTrack() {
    if (g.playIndex > 0) playAt(g.playIndex - 1);
}

static void openFile() {
    wchar_t file[32768] = {0};
    OPENFILENAMEW ofn = {0};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g.hMain;
    ofn.lpstrFilter =
        L"Arquivos de mídia\0*.mp4;*.mkv;*.avi;*.mov;*.webm;*.m4v;*.wmv;*.flv;*.mpg;*.mpeg;*.ts;*.mp3;*.flac;*.wav;*.ogg;*.m4a;*.aac\0"
        L"Vídeo\0*.mp4;*.mkv;*.avi;*.mov;*.webm;*.m4v;*.wmv;*.flv;*.mpg;*.mpeg;*.ts\0"
        L"Áudio\0*.mp3;*.flac;*.wav;*.ogg;*.m4a;*.aac\0"
        L"Todos os arquivos\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = 32768;
    if (!g.lastDir.empty()) ofn.lpstrInitialDir = g.lastDir.c_str();
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_ALLOWMULTISELECT | OFN_EXPLORER;
    if (GetOpenFileNameW(&ofn)) {
        std::vector<std::wstring> files;
        std::wstring dir = file;
        wchar_t* p = file + dir.size() + 1;
        if (*p == 0) {
            files.push_back(dir);
        } else {
            if (!dir.empty() && dir.back() != L'\\') dir += L'\\';
            while (*p) {
                files.push_back(dir + p);
                p += wcslen(p) + 1;
            }
        }
        if (!files.empty()) openFiles(files);
    }
}

static void playPause() {
    if (!g.mp) { openFile(); return; }
    if (libvlc_media_player_is_playing(g.mp)) {
        libvlc_media_player_pause(g.mp);
    } else {
        if (g.length > 0 && g.curTime >= g.length - 1000000)
            libvlc_media_player_set_position(g.mp, 0.0, true);
        libvlc_media_player_play(g.mp);
    }
    g.playing = libvlc_media_player_is_playing(g.mp);
    InvalidateRect(g.hMain, &g.rcBar, FALSE);
}

static void stop() {
    if (g.mp) libvlc_media_player_stop_async(g.mp);
    g.playing = false;
    g.curTime = 0; g.seekPos = 0.0;
    InvalidateRect(g.hMain, &g.rcBar, FALSE);
}

static void seekTo(double pos) {
    pos = clampd(pos, 0.0, 1.0);
    if (g.mp) libvlc_media_player_set_position(g.mp, pos, true);
    g.seekPos = pos;
}

static void seekBy(long long deltaUs) {
    if (!g.mp || g.length <= 0) return;
    long long t = (long long)libvlc_media_player_get_time(g.mp) + deltaUs;
    if (t < 0) t = 0;
    if (t > g.length) t = g.length;
    libvlc_media_player_set_time(g.mp, (libvlc_time_t)t, true);
}

static void setVolume(int v) {
    v = clampi(v, 0, 100);
    g.volume = v;
    if (g.mp) {
        libvlc_audio_set_volume(g.mp, v);
        if (v > 0) libvlc_audio_set_mute(g.mp, 0);
    }
    if (v > 0) g.muted = false;
    wchar_t vb[32]; swprintf(vb, 32, L"Volume: %d%%", v);
    showOsd(vb);
    InvalidateRect(g.hMain, &g.rcBar, FALSE);
}

static void toggleMute() {
    g.muted = !g.muted;
    if (g.mp) libvlc_audio_set_mute(g.mp, g.muted ? 1 : 0);
    showOsd(g.muted ? L"Mudo" : L"Som");
    InvalidateRect(g.hMain, &g.rcBar, FALSE);
}

static void setRate(float r) {
    g.rate = clampf(r, 0.25f, 4.0f);
    if (g.mp) libvlc_media_player_set_rate(g.mp, g.rate);
    showOsd(std::wstring(L"Velocidade: ") + fmtRate(g.rate));
    InvalidateRect(g.hMain, &g.rcBar, FALSE);
}

static void cycleRate(bool up) {
    static const float rates[] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f, 3.0f };
    int idx = 2;
    for (int i = 0; i < 7; ++i)
        if (g.rate > rates[i] - 0.001f && g.rate < rates[i] + 0.001f) { idx = i; break; }
    idx = clampi(up ? idx + 1 : idx - 1, 0, 6);
    setRate(rates[idx]);
}

// ---------------------------------------------------------------------------
// OSD (feedback sobre o vídeo)
// ---------------------------------------------------------------------------
static void showOsd(const std::wstring& text) {
    if (!g.hOsd) return;
    g.osdText = text;
    g.osdUntil = GetTickCount() + 1600;

    HDC dc = GetDC(g.hMain);
    HGDIOBJ of = SelectObject(dc, g.titleFont);
    SIZE sz = {0};
    GetTextExtentPoint32W(dc, text.c_str(), (int)text.size(), &sz);
    SelectObject(dc, of);
    ReleaseDC(g.hMain, dc);

    int w = sz.cx + 56, h = 44;
    RECT rc; GetClientRect(g.hMain, &rc);
    MoveWindow(g.hOsd, (rc.right - w) / 2, 24, w, h, TRUE);
    SetWindowPos(g.hOsd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    ShowWindow(g.hOsd, SW_SHOW);
    InvalidateRect(g.hOsd, nullptr, TRUE);
}

static LRESULT CALLBACK OsdProc(HWND h, UINT m, WPARAM wp, LPARAM lp) {
    switch (m) {
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        RECT rc; GetClientRect(h, &rc);
        HBRUSH bg = CreateSolidBrush(RGB(0x14, 0x14, 0x14));
        HPEN pen = CreatePen(PS_SOLID, 1, kTrack);
        HGDIOBJ ob = SelectObject(dc, bg), op = SelectObject(dc, pen);
        RoundRect(dc, rc.left, rc.top, rc.right, rc.bottom, 8, 8);
        SelectObject(dc, ob); SelectObject(dc, op);
        DeleteObject(bg); DeleteObject(pen);
        SetTextColor(dc, kText);
        SetBkMode(dc, TRANSPARENT);
        HGDIOBJ of = SelectObject(dc, g.titleFont);
        DrawTextW(dc, g.osdText.c_str(), -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        SelectObject(dc, of);
        EndPaint(h, &ps);
        return 0;
    }
    }
    return DefWindowProcW(h, m, wp, lp);
}

// ---------------------------------------------------------------------------
// Recursos extras: repetição, proporção, captura
// ---------------------------------------------------------------------------
static void cycleLoop() {
    g.loopMode = (g.loopMode + 1) % 3;
    const wchar_t* names[] = { L"Repetição: desligada", L"Repetição: uma faixa", L"Repetição: todas" };
    showOsd(names[g.loopMode]);
}

static const char* kAspects[] = { nullptr, "fill", "16:9", "4:3", "1:1" };
static const wchar_t* kAspectNames[] = { L"Proporção: original", L"Proporção: preencher", L"Proporção: 16:9", L"Proporção: 4:3", L"Proporção: 1:1" };

static void applyAspectToPlayer() {
    if (g.mp && g.aspectIdx > 0)
        libvlc_video_set_aspect_ratio(g.mp, kAspects[g.aspectIdx]);
}

static void cycleAspect() {
    if (!g.mp) return;
    g.aspectIdx = (g.aspectIdx + 1) % 5;
    libvlc_video_set_aspect_ratio(g.mp, kAspects[g.aspectIdx]);
    showOsd(kAspectNames[g.aspectIdx]);
}

static std::wstring snapshotPath() {
    wchar_t profile[MAX_PATH];
    GetEnvironmentVariableW(L"USERPROFILE", profile, MAX_PATH);
    std::wstring dir = std::wstring(profile) + L"\\Pictures\\SantoVideoPlayer";
    CreateDirectoryW((std::wstring(profile) + L"\\Pictures").c_str(), nullptr);
    CreateDirectoryW(dir.c_str(), nullptr);
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t name[64];
    swprintf(name, 64, L"\\snap-%04d%02d%02d-%02d%02d%02d.png",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    return dir + name;
}

static void takeSnapshot() {
    if (!g.mp) return;
    std::wstring p = snapshotPath();
    std::string path = w2a(p);
    libvlc_video_take_snapshot(g.mp, 0, path.c_str(), 0, 0);
    // confere se o arquivo foi realmente gravado (o build light pode não ter
    // codificador PNG/JPEG, e aí a captura falha silenciosamente)
    bool ok = GetFileAttributesW(p.c_str()) != INVALID_FILE_ATTRIBUTES;
    showOsd(ok ? L"Captura salva" : L"Falha ao capturar (sem encoder PNG)");
}

// ---------------------------------------------------------------------------
// Shader CRT
// ---------------------------------------------------------------------------
// Recria a instância libvlc com a config CRT atual, preservando posição/pausa.
static void recreateInstance() {
    libvlc_time_t saved = -1;
    bool wasPlaying = g.playing;
    if (g.mp && g.length > 0)
        saved = libvlc_media_player_get_time(g.mp);

    closePlayer();
    if (g.inst) { libvlc_release(g.inst); g.inst = nullptr; }
    ensureInstance();
    if (!g.inst) return;

    if (g.file.empty()) return;
    startPlayback(g.file);
    g.pendingSeek = saved;
    applyAspectToPlayer();
    if (!wasPlaying && g.mp)
        libvlc_media_player_set_pause(g.mp, true);
}

static void applyPreset(int idx) {
    g.presetIndex = idx;
    const Preset& p = kPresets[idx];
    g.cfg.enabled = p.enabled;
    g.cfg.scanline_strength = p.scanline;
    g.cfg.mask_strength = p.mask;
    g.cfg.scanline_period = p.period;
    g.cfg.curvature = p.curvature;
    if (!g.file.empty()) recreateInstance();
    if (g.hFx) InvalidateRect(g.hFx, nullptr, FALSE);
}

// ---------------------------------------------------------------------------
// Tela cheia
// ---------------------------------------------------------------------------
static void enterFullscreen() {
    if (g.fullscreen) return;
    g.fullscreen = true;
    g.wp.length = sizeof(g.wp);
    GetWindowPlacement(g.hMain, &g.wp);

    HMONITOR mon = MonitorFromWindow(g.hMain, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = { sizeof(mi) };
    GetMonitorInfo(mon, &mi);

    SetWindowLongPtrW(g.hMain, GWL_STYLE, (LONG_PTR)(WS_POPUP | WS_VISIBLE));
    SetWindowPos(g.hMain, HWND_TOP,
        mi.rcMonitor.left, mi.rcMonitor.top,
        mi.rcMonitor.right - mi.rcMonitor.left,
        mi.rcMonitor.bottom - mi.rcMonitor.top,
        SWP_FRAMECHANGED);
    layout();
    g.controlsVisible = true;
    g.lastMouseMove = GetTickCount();
    InvalidateRect(g.hMain, nullptr, FALSE);
}

static void exitFullscreen() {
    if (!g.fullscreen) return;
    g.fullscreen = false;
    g.controlsVisible = true;
    SetWindowLongPtrW(g.hMain, GWL_STYLE, (LONG_PTR)(WS_OVERLAPPEDWINDOW | WS_VISIBLE));
    SetWindowPlacement(g.hMain, &g.wp);
    SetWindowPos(g.hMain, nullptr, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
    layout();
    InvalidateRect(g.hMain, nullptr, FALSE);
}

static void toggleFullscreen() {
    if (g.fullscreen) exitFullscreen(); else enterFullscreen();
}

static void showControls() {
    g.lastMouseMove = GetTickCount();
    if (!g.controlsVisible) {
        g.controlsVisible = true;
        layout();
        InvalidateRect(g.hMain, nullptr, FALSE);
    }
}

static void hideControls() {
    if (g.fullscreen && g.controlsVisible) {
        g.controlsVisible = false;
        layout();
        InvalidateRect(g.hMain, nullptr, FALSE);
    }
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
static void layout() {
    RECT rc; GetClientRect(g.hMain, &rc);
    int w = rc.right, hh = rc.bottom;

    bool show = !g.fullscreen || g.controlsVisible;
    int barH = show ? kBarH : 0;

    g.rcVideo = { 0, 0, w, hh - barH };
    g.rcBar   = { 0, hh - barH, w, hh };
    MoveWindow(g.hVideo, 0, 0, w, hh - barH, TRUE);
    if (!show) return;

    const int pad = 10;
    const int timeW = 170;
    g.rcSeek = { pad, g.rcBar.top + 8, w - pad - timeW - 8, g.rcBar.top + 20 };

    int y = g.rcBar.top + 40, bh = 30;
    int x = pad;
    g.btn[B_OPEN] = { x,        y, x + 40, y + bh }; x += 44;
    g.btn[B_PREV] = { x,        y, x + 34, y + bh }; x += 38;
    g.btn[B_PLAY] = { x,        y, x + 48, y + bh }; x += 52;
    g.btn[B_STOP] = { x,        y, x + 38, y + bh }; x += 42;
    g.btn[B_NEXT] = { x,        y, x + 34, y + bh }; x += 38;
    g.btn[B_MUTE] = { x,        y, x + 34, y + bh }; x += 38;
    g.rcVol       = { x, y + (bh - 6) / 2, x + 110, y + (bh - 6) / 2 + 6 };
    x += 118;
    g.btn[B_FULL] = { w - pad - 40, y, w - pad, y + bh };
    g.btn[B_FX]   = { w - pad - 40 - 44, y, w - pad - 44, y + bh };

    if (g.hFx && g.fxOpen) {
        MoveWindow(g.hFx, 12, 12, 300, 352, TRUE);
        SetWindowPos(g.hFx, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    }
}

// ---------------------------------------------------------------------------
// Desenho
// ---------------------------------------------------------------------------
static void drawButton(HDC dc, RECT r, const wchar_t* glyph, bool hover, bool accent) {
    HBRUSH bg = CreateSolidBrush(accent ? (hover ? RGB(0xff, 0x9c, 0x30) : kAccent)
                                        : (hover ? kBtnHov : kBtnBg));
    HPEN pen = CreatePen(PS_SOLID, 1, accent ? kAccent : kTrack);
    HGDIOBJ ob = SelectObject(dc, bg), op = SelectObject(dc, pen);
    RoundRect(dc, r.left, r.top, r.right, r.bottom, 6, 6);
    SelectObject(dc, ob); SelectObject(dc, op);
    DeleteObject(bg); DeleteObject(pen);

    SetTextColor(dc, accent ? RGB(0x1a, 0x1a, 0x1a) : kText);
    SetBkMode(dc, TRANSPARENT);
    HGDIOBJ of = SelectObject(dc, g.iconFont);
    DrawTextW(dc, glyph, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    SelectObject(dc, of);
}

static void drawSlider(HDC dc, RECT r, double pos) {
    pos = clampd(pos, 0.0, 1.0);
    int midY = (r.top + r.bottom) / 2;
    int fx = r.left + (int)((r.right - r.left) * pos);

    HBRUSH track = CreateSolidBrush(kTrack);
    RECT tr = { r.left, midY - 3, r.right, midY + 3 };
    FillRect(dc, &tr, track); DeleteObject(track);

    HBRUSH fill = CreateSolidBrush(kAccent);
    RECT fr = { r.left, midY - 3, fx, midY + 3 };
    FillRect(dc, &fr, fill); DeleteObject(fill);

    HBRUSH knob = CreateSolidBrush(RGB(0xff, 0xff, 0xff));
    HGDIOBJ op = SelectObject(dc, GetStockObject(NULL_PEN));
    Ellipse(dc, fx - 6, midY - 6, fx + 6, midY + 6);
    SelectObject(dc, op); DeleteObject(knob);
}

static void PaintApp(HDC dc) {
    RECT rc; GetClientRect(g.hMain, &rc);
    FillRect(dc, &rc, (HBRUSH)GetStockObject(BLACK_BRUSH));

    if (!g.controlsVisible && g.fullscreen) return;

    HBRUSH bar = CreateSolidBrush(kBarBg);
    FillRect(dc, &g.rcBar, bar); DeleteObject(bar);

    HBRUSH sep = CreateSolidBrush(kTrack);
    RECT sr = { g.rcBar.left, g.rcBar.top, g.rcBar.right, g.rcBar.top + 1 };
    FillRect(dc, &sr, sep); DeleteObject(sep);

    drawSlider(dc, g.rcSeek, g.seekPos);

    SetTextColor(dc, kTextDim);
    SetBkMode(dc, TRANSPARENT);
    HGDIOBJ of = SelectObject(dc, g.uiFont);
    std::wstring ts = fmtTime(g.curTime) + L" / " + fmtTime(g.length);
    if (g.rate > 1.001f || g.rate < 0.999f)
        ts = fmtRate(g.rate) + L"  " + ts;
    RECT rt = { g.rcSeek.right + 8, g.rcSeek.top - 3, g.rcBar.right - 10, g.rcSeek.top + 17 };
    DrawTextW(dc, ts.c_str(), -1, &rt, DT_RIGHT | DT_VCENTER | DT_SINGLELINE);

    drawButton(dc, g.btn[B_OPEN], kGlyphOpen, g.hover == B_OPEN, false);
    drawButton(dc, g.btn[B_PREV], kGlyphPrev, g.hover == B_PREV, false);
    drawButton(dc, g.btn[B_PLAY], g.playing ? kGlyphPause : kGlyphPlay,
               g.hover == B_PLAY, true);
    drawButton(dc, g.btn[B_STOP], kGlyphStop, g.hover == B_STOP, false);
    drawButton(dc, g.btn[B_NEXT], kGlyphNext, g.hover == B_NEXT, false);
    drawButton(dc, g.btn[B_MUTE], g.muted ? kGlyphMute : kGlyphVol,
               g.hover == B_MUTE, false);
    drawButton(dc, g.btn[B_FX],   kGlyphFx,   g.hover == B_FX || g.fxOpen, false);
    drawButton(dc, g.btn[B_FULL], g.fullscreen ? kGlyphRestore : kGlyphFull,
               g.hover == B_FULL, false);

    drawSlider(dc, g.rcVol, g.muted ? 0.0 : (g.volume / 100.0));
    SelectObject(dc, of);
}

// ---------------------------------------------------------------------------
// Painel de efeitos CRT
// ---------------------------------------------------------------------------
static const int kFxW = 300, kFxH = 352;

struct FxLayout {
    RECT presets[kPresetCount];
    RECT scan, mask;
};

static FxLayout fxLayout() {
    FxLayout L{};
    const int pad = 12;
    int y = 44;
    for (int i = 0; i < kPresetCount; ++i) {
        L.presets[i] = { pad, y, kFxW - pad, y + 36 };
        y += 42;
    }
    y += 6;
    L.scan = { pad, y + 14, kFxW - pad, y + 22 };
    y += 44;
    L.mask = { pad, y + 14, kFxW - pad, y + 22 };
    return L;
}

static void PaintFx(HDC dc) {
    RECT rc = { 0, 0, kFxW, kFxH };
    HBRUSH bg = CreateSolidBrush(kPanelBg);
    FillRect(dc, &rc, bg); DeleteObject(bg);

    HPEN border = CreatePen(PS_SOLID, 1, kTrack);
    HGDIOBJ op = SelectObject(dc, border);
    HGDIOBJ ob = SelectObject(dc, GetStockObject(NULL_BRUSH));
    Rectangle(dc, rc.left, rc.top, rc.right, rc.bottom);
    SelectObject(dc, op); SelectObject(dc, ob);
    DeleteObject(border);

    SetBkMode(dc, TRANSPARENT);

    SetTextColor(dc, kText);
    HGDIOBJ ot = SelectObject(dc, g.titleFont);
    RECT tr = { 12, 8, kFxW - 12, 34 };
    DrawTextW(dc, L"Efeitos CRT", -1, &tr, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    SelectObject(dc, ot);

    FxLayout L = fxLayout();

    HGDIOBJ ou = SelectObject(dc, g.uiFont);
    for (int i = 0; i < kPresetCount; ++i) {
        bool active = (i == g.presetIndex);
        RECT r = L.presets[i];
        HBRUSH b = CreateSolidBrush(active ? RGB(0x3a, 0x2a, 0x10) : kBtnBg);
        HPEN p = CreatePen(PS_SOLID, 1, active ? kAccent : kTrack);
        HGDIOBJ o1 = SelectObject(dc, b), o2 = SelectObject(dc, p);
        RoundRect(dc, r.left, r.top, r.right, r.bottom, 5, 5);
        SelectObject(dc, o1); SelectObject(dc, o2);
        DeleteObject(b); DeleteObject(p);
        SetTextColor(dc, active ? kAccent : kText);
        RECT rr = { r.left + 10, r.top, r.right - 10, r.bottom };
        DrawTextW(dc, kPresets[i].name, -1, &rr, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    }

    SetTextColor(dc, kTextDim);
    RECT ls = { 12, L.scan.top - 22, kFxW - 12, L.scan.top - 4 };
    DrawTextW(dc, L"Scanlines", -1, &ls, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    drawSlider(dc, L.scan, g.cfg.scanline_strength);

    RECT lm = { 12, L.mask.top - 22, kFxW - 12, L.mask.top - 4 };
    DrawTextW(dc, L"Máscara", -1, &lm, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    drawSlider(dc, L.mask, g.cfg.mask_strength);

    SelectObject(dc, ou);
}

static LRESULT CALLBACK FxProc(HWND h, UINT m, WPARAM wp, LPARAM lp) {
    switch (m) {
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        PaintFx(dc);
        EndPaint(h, &ps);
        return 0;
    }
    case WM_LBUTTONDOWN: {
        int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
        POINT p = { x, y };
        FxLayout L = fxLayout();
        for (int i = 0; i < kPresetCount; ++i) {
            if (PtInRect(&L.presets[i], p)) {
                applyPreset(i);
                g.fxOpen = false;
                ShowWindow(g.hFx, SW_HIDE);
                InvalidateRect(g.hMain, &g.rcBar, FALSE);
                return 0;
            }
        }
        if (PtInRect(&L.scan, p)) { SetCapture(h); g.fxDragScan = true; return 0; }
        if (PtInRect(&L.mask, p)) { SetCapture(h); g.fxDragMask = true; return 0; }
        return 0;
    }
    case WM_MOUSEMOVE: {
        int x = GET_X_LPARAM(lp);
        FxLayout L = fxLayout();
        if (g.fxDragScan) {
            g.cfg.scanline_strength = clampd((double)(x - L.scan.left) / (double)(L.scan.right - L.scan.left), 0.0, 1.0);
            g.cfg.enabled = true;
            InvalidateRect(h, nullptr, FALSE);
            return 0;
        }
        if (g.fxDragMask) {
            g.cfg.mask_strength = clampd((double)(x - L.mask.left) / (double)(L.mask.right - L.mask.left), 0.0, 1.0);
            g.cfg.enabled = true;
            InvalidateRect(h, nullptr, FALSE);
            return 0;
        }
        return 0;
    }
    case WM_LBUTTONUP:
        if (g.fxDragScan || g.fxDragMask) {
            g.fxDragScan = g.fxDragMask = false;
            ReleaseCapture();
            if (!g.file.empty()) recreateInstance();
            InvalidateRect(h, nullptr, FALSE);
        }
        return 0;
    }
    return DefWindowProcW(h, m, wp, lp);
}

// ---------------------------------------------------------------------------
// Vídeo host
// ---------------------------------------------------------------------------
static LRESULT CALLBACK VideoHostProc(HWND h, UINT m, WPARAM wp, LPARAM lp) {
    switch (m) {
    case WM_ERASEBKGND: {
        RECT rc; GetClientRect(h, &rc);
        HDC dc = (HDC)wp;
        FillRect(dc, &rc, (HBRUSH)GetStockObject(BLACK_BRUSH));
        return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(h, &ps);
        if (!g.mp) {
            // estado vazio
            SetBkMode(dc, TRANSPARENT);
            HGDIOBJ of = SelectObject(dc, g.titleFont);
            SetTextColor(dc, kText);
            RECT rc; GetClientRect(h, &rc);
            RECT tr = rc; tr.top = rc.bottom / 2 - 60; tr.bottom = rc.bottom / 2 - 30;
            DrawTextW(dc, L"Santo Video Player", -1, &tr, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            SelectObject(dc, of);

            HGDIOBJ oh = SelectObject(dc, g.hintFont);
            SetTextColor(dc, kTextDim);
            RECT hr = rc; hr.top = rc.bottom / 2 - 10; hr.bottom = rc.bottom / 2 + 50;
            DrawTextW(dc, L"Arraste um vídeo aqui\r\nou clique em Abrir", -1, &hr, DT_CENTER | DT_VCENTER);
            SelectObject(dc, oh);
        } else if (!g.hasVideo) {
            SetBkMode(dc, TRANSPARENT);
            HGDIOBJ of = SelectObject(dc, g.titleFont);
            SetTextColor(dc, kText);
            RECT rc; GetClientRect(h, &rc);
            RECT tr = rc; tr.top = rc.bottom / 2 - 34; tr.bottom = rc.bottom / 2 - 4;
            DrawTextW(dc, L"♪  Áudio", -1, &tr, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            SelectObject(dc, of);

            HGDIOBJ oh = SelectObject(dc, g.hintFont);
            SetTextColor(dc, kTextDim);
            RECT hr = rc; hr.top = rc.bottom / 2; hr.bottom = rc.bottom / 2 + 40;
            const wchar_t* base = wcsrchr(g.file.c_str(), L'\\');
            std::wstring name = base ? (base + 1) : g.file.c_str();
            DrawTextW(dc, name.c_str(), -1, &hr, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            SelectObject(dc, oh);
        }
        EndPaint(h, &ps);
        return 0;
    }
    case WM_LBUTTONDOWN:
        if (g.fullscreen) {
            if (!g.controlsVisible) showControls();
        } else {
            g.pendingClick = true;
            SetTimer(g.hMain, kClickTimerId, GetDoubleClickTime() + 50, nullptr);
        }
        return 0;
    case WM_LBUTTONDBLCLK:
        g.pendingClick = false;
        KillTimer(g.hMain, kClickTimerId);
        toggleFullscreen();
        return 0;
    case WM_DROPFILES:
        SendMessageW(g.hMain, WM_DROPFILES, wp, lp);
        return 0;
    }
    return DefWindowProcW(h, m, wp, lp);
}

// ---------------------------------------------------------------------------
// Window proc principal
// ---------------------------------------------------------------------------
static double posFromSeek(int x) {
    return clampd((double)(x - g.rcSeek.left) / (double)(g.rcSeek.right - g.rcSeek.left), 0.0, 1.0);
}
static int volFromX(int x) {
    return (int)(clampd((double)(x - g.rcVol.left) / (double)(g.rcVol.right - g.rcVol.left), 0.0, 1.0) * 100.0 + 0.5);
}

static void onButton(int i) {
    switch (i) {
    case B_OPEN: openFile(); break;
    case B_PREV: prevTrack(); break;
    case B_PLAY: playPause(); break;
    case B_STOP: stop(); break;
    case B_NEXT: nextTrack(); break;
    case B_MUTE: toggleMute(); break;
    case B_FX:
        g.fxOpen = !g.fxOpen;
        ShowWindow(g.hFx, g.fxOpen ? SW_SHOW : SW_HIDE);
        if (g.fxOpen) {
            MoveWindow(g.hFx, 12, 12, kFxW, kFxH, TRUE);
            SetWindowPos(g.hFx, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
        }
        InvalidateRect(g.hMain, &g.rcBar, FALSE);
        break;
    case B_FULL: toggleFullscreen(); break;
    }
}

static void onKey(WPARAM vk) {
    bool ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
    if (vk >= '0' && vk <= '9') { seekTo((double)(vk - '0') / 10.0); return; }
    switch (vk) {
    case VK_SPACE:   playPause(); break;
    case 'F': case VK_F11: toggleFullscreen(); break;
    case VK_ESCAPE:  if (g.fullscreen) exitFullscreen(); break;
    case VK_LEFT:    seekBy(-5000000); break;
    case VK_RIGHT:   seekBy(5000000); break;
    case VK_UP:      setVolume(g.volume + 5); break;
    case VK_DOWN:    setVolume(g.volume - 5); break;
    case 'M':        toggleMute(); break;
    case 'S':        stop(); break;
    case 'P':        prevTrack(); break;
    case 'N':        nextTrack(); break;
    case 'O':        if (ctrl) openFile(); break;
    case 'E':        if (ctrl) onButton(B_FX); break;
    case 'L':        cycleLoop(); break;
    case 'C':        takeSnapshot(); break;
    case 'A':        cycleAspect(); break;
    case VK_OEM_4:   cycleRate(false); break;  // '['
    case VK_OEM_6:   cycleRate(true);  break;  // ']'
    case VK_OEM_PLUS: if (ctrl) setRate(1.0f); break;  // Ctrl+=
    }
}

static void onTimer() {
    if (g.mp) {
        bool nowPlaying = libvlc_media_player_is_playing(g.mp);
        if (g.playing && !nowPlaying) {
            libvlc_state_t st = libvlc_media_player_get_state(g.mp);
            if (st == libvlc_Stopped || st == libvlc_Error) {
                g.playing = false;
                if (st == libvlc_Error) showOsd(L"Erro ao reproduzir");
                if (g.loopMode == 1) playAt(g.playIndex);
                else if (g.loopMode == 2) playAt((g.playIndex + 1) % (int)g.playlist.size());
                else nextTrack();
                return;
            }
        }
        g.playing = nowPlaying;
        if (!g.seekDrag) {
            g.curTime = libvlc_media_player_get_time(g.mp);
            g.length  = libvlc_media_player_get_length(g.mp);
            g.seekPos = (g.length > 0) ? clampd((double)g.curTime / (double)g.length, 0.0, 1.0) : 0.0;
        }
        bool hasVideoTrack = true;
        libvlc_media_tracklist_t* tl = libvlc_media_player_get_tracklist(g.mp, libvlc_track_video, false);
        if (tl) {
            hasVideoTrack = libvlc_media_tracklist_count(tl) > 0;
            libvlc_media_tracklist_delete(tl);
        }
        if (hasVideoTrack) {
            g.noVoutSince = 0;
            if (!g.hasVideo) { g.hasVideo = true; InvalidateRect(g.hVideo, nullptr, TRUE); }
        } else if (g.noVoutSince == 0) {
            g.noVoutSince = GetTickCount();
        } else if ((GetTickCount() - g.noVoutSince) > 1500 && g.hasVideo) {
            g.hasVideo = false;
            InvalidateRect(g.hVideo, nullptr, TRUE);
        }
    }
    if (g.pendingSeek >= 0 && g.mp && g.length > 0) {
        libvlc_media_player_set_time(g.mp, g.pendingSeek, true);
        g.pendingSeek = -1;
    }
    if (g.fullscreen && g.controlsVisible &&
        (GetTickCount() - g.lastMouseMove) > 2500) {
        hideControls();
    }
    if (!g.osdText.empty() && GetTickCount() > g.osdUntil) {
        g.osdText.clear();
        if (g.hOsd) ShowWindow(g.hOsd, SW_HIDE);
    }
    InvalidateRect(g.hMain, &g.rcBar, FALSE);
}

static LRESULT CALLBACK MainWndProc(HWND h, UINT m, WPARAM wp, LPARAM lp) {
    switch (m) {
    case WM_CREATE: {
        g.hMain = h;

        g.uiFont = CreateFontW(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        g.titleFont = CreateFontW(-17, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        g.iconFont = CreateFontW(-20, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe MDL2 Assets");
        g.hintFont = CreateFontW(-22, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

        g.hVideo = CreateWindowW(L"SantoVideoHost", nullptr,
            WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0, 0, 0, 0,
            h, nullptr, GetModuleHandleW(nullptr), nullptr);

        g.hFx = CreateWindowW(L"SantoFxPanel", nullptr,
            WS_CHILD | WS_CLIPSIBLINGS, 0, 0, kFxW, kFxH,
            h, nullptr, GetModuleHandleW(nullptr), nullptr);

        g.hOsd = CreateWindowExW(WS_EX_TRANSPARENT, L"SantoOsd", nullptr,
            WS_CHILD | WS_CLIPSIBLINGS, 0, 0, 300, 44,
            h, nullptr, GetModuleHandleW(nullptr), nullptr);

        DragAcceptFiles(h, TRUE);
        DragAcceptFiles(g.hVideo, TRUE);
        applyDarkTitlebar(h);
        SetTimer(h, kTimerId, kTimerMs, nullptr);
        layout();
        return 0;
    }
    case WM_SIZE:       layout(); return 0;
    case WM_GETMINMAXINFO:
        ((MINMAXINFO*)lp)->ptMinTrackSize.x = 480;
        ((MINMAXINFO*)lp)->ptMinTrackSize.y = 320;
        return 0;
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(h, &ps);
        RECT rc; GetClientRect(h, &rc);
        HDC mem = CreateCompatibleDC(dc);
        HBITMAP bmp = CreateCompatibleBitmap(dc, rc.right, rc.bottom);
        HGDIOBJ ob = SelectObject(mem, bmp);
        PaintApp(mem);
        BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
        SelectObject(mem, ob);
        DeleteObject(bmp);
        DeleteDC(mem);
        EndPaint(h, &ps);
        return 0;
    }
    case WM_LBUTTONDOWN: {
        int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
        POINT p = { x, y };
        if (g.controlsVisible && PtInRect(&g.rcSeek, p)) {
            g.seekDrag = true; SetCapture(h);
            seekTo(posFromSeek(x));
            return 0;
        }
        if (g.controlsVisible && PtInRect(&g.rcVol, p)) {
            g.volDrag = true; SetCapture(h);
            setVolume(volFromX(x));
            return 0;
        }
        for (int i = 0; i < B_COUNT; ++i)
            if (PtInRect(&g.btn[i], p)) { onButton(i); return 0; }
        return 0;
    }
    case WM_MOUSEMOVE: {
        g.lastMouseMove = GetTickCount();
        int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
        POINT p = { x, y };
        if (g.seekDrag) { seekTo(posFromSeek(x)); return 0; }
        if (g.volDrag)  { setVolume(volFromX(x)); return 0; }
        if (!g.tracking) {
            TRACKMOUSEEVENT t = { sizeof(t), TME_LEAVE, h, 0 };
            TrackMouseEvent(&t);
            g.tracking = true;
        }
        int nh = -1;
        if (g.controlsVisible)
            for (int i = 0; i < B_COUNT; ++i)
                if (PtInRect(&g.btn[i], p)) { nh = i; break; }
        if (nh != g.hover) { g.hover = nh; InvalidateRect(h, &g.rcBar, FALSE); }
        return 0;
    }
    case WM_LBUTTONUP:
        if (g.seekDrag || g.volDrag) {
            g.seekDrag = g.volDrag = false;
            ReleaseCapture();
            InvalidateRect(h, &g.rcBar, FALSE);
        }
        return 0;
    case WM_MOUSELEAVE:
        g.hover = -1; g.tracking = false;
        InvalidateRect(h, &g.rcBar, FALSE);
        return 0;
    case WM_MOUSEWHEEL: {
        int delta = GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA;
        setVolume(g.volume + delta * 4);
        return 0;
    }
    case WM_KEYDOWN:    onKey(wp); return 0;
    case WM_TIMER:
        if (wp == kTimerId) onTimer();
        else if (wp == kClickTimerId) {
            KillTimer(h, kClickTimerId);
            if (g.pendingClick) { g.pendingClick = false; playPause(); }
        }
        return 0;
    case WM_DROPFILES: {
        HDROP hd = (HDROP)wp;
        int n = DragQueryFileW(hd, 0xFFFFFFFF, nullptr, 0);
        std::vector<std::wstring> files;
        for (int i = 0; i < n; ++i) {
            wchar_t f[4096];
            if (DragQueryFileW(hd, i, f, 4096)) files.push_back(f);
        }
        DragFinish(hd);
        if (!files.empty()) openFiles(files);
        return 0;
    }
    case WM_CLOSE:
        saveSettings();
        stop();
        closePlayer();
        if (g.inst) { libvlc_release(g.inst); g.inst = nullptr; }
        DestroyWindow(h);
        return 0;
    case WM_DESTROY:
        KillTimer(h, kTimerId);
        if (g.uiFont)    DeleteObject(g.uiFont);
        if (g.titleFont) DeleteObject(g.titleFont);
        if (g.iconFont)  DeleteObject(g.iconFont);
        if (g.hintFont)  DeleteObject(g.hintFont);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(h, m, wp, lp);
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, PWSTR, int nShow) {
    loadSettings();
    ensureInstance();

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = MainWndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = L"SantoVideoPlayerWnd";
    RegisterClassW(&wc);

    WNDCLASSW vc = {0};
    vc.lpfnWndProc = VideoHostProc;
    vc.hInstance = hInst;
    vc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    vc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    vc.lpszClassName = L"SantoVideoHost";
    RegisterClassW(&vc);

    WNDCLASSW fc = {0};
    fc.lpfnWndProc = FxProc;
    fc.hInstance = hInst;
    fc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    fc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    fc.lpszClassName = L"SantoFxPanel";
    RegisterClassW(&fc);

    WNDCLASSW oc = {0};
    oc.lpfnWndProc = OsdProc;
    oc.hInstance = hInst;
    oc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    oc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    oc.lpszClassName = L"SantoOsd";
    RegisterClassW(&oc);

    int x = CW_USEDEFAULT, y = CW_USEDEFAULT, w = 960, h = 600;
    if (g.hasInitialRect) { x = g.initialRect.left; y = g.initialRect.top; w = g.initialRect.right - g.initialRect.left; h = g.initialRect.bottom - g.initialRect.top; }

    HWND hwnd = CreateWindowW(wc.lpszClassName, L"Santo Video Player",
        WS_OVERLAPPEDWINDOW, x, y, w, h,
        nullptr, nullptr, hInst, nullptr);
    if (!hwnd) return 1;

    ShowWindow(hwnd, nShow);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return (int)msg.wParam;
}
