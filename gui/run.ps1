# Roda o Santo Video Player.
# O executável usa o libvlc do VLC oficial; o PATH aponta para a instalação do
# VLC para o Windows conseguir carregar libvlc.dll e o VLC achar seus plugins.
$env:PATH = "D:\vlc-install;$env:PATH"
& "$PSScriptRoot\SantoVideoPlayer.exe"
