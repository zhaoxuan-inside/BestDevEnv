# Konsole 统一 profile（cfg-map: konsole-profile；落位 $XDG_DATA_HOME/konsole/devspace.profile）
# v0.19：终端字体/外观统一——JetBrainsMono Nerd Font（M1.9 字体能力安装）；默认 profile 指针由
# terminal 能力经 kwriteconfig5 写入 konsolerc（KConfig API 幂等，不整文件覆盖）
[General]
Name=devspace

[Appearance]
ColorScheme=BreezeDark
Font=JetBrainsMono Nerd Font,12,-1,5,50,0,0,0,0,0
UseFontLineCharacters=true

[Scrolling]
ScrollBarFullScreen=false

[Terminal Features]
BoldIntense=false
CursorShape=1
