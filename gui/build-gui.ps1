# Rebuild da GUI do Santo Video Player (exige o toolchain MinGW + o build do VLC)
$env:PATH = "C:\Users\Matheus\scoop\apps\mingw\current\bin;$env:PATH"
g++ santo-player.cpp -o SantoVideoPlayer.exe `
  -I D:/vlc-install/sdk/include D:/vlc-install/libvlc.dll.a `
  -lcomdlg32 -lgdi32 -luser32 -lole32 -lshell32 `
  -mwindows -municode -static-libgcc -static-libstdc++ -std=c++17
Write-Output "exit=$LASTEXITCODE"
