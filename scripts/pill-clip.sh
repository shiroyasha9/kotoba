#!/bin/zsh
# Encodes the pill's clip frames (`kotoba --pill-clip <folder>`, App/PillClipSnapshots.swift): one H.264 MP4 per clip at
# 30 fps, and a copy at a quarter of the speed to study a change. The frames stay in the folder.
# Usage: scripts/pill-clip.sh <folder with one frame folder per clip>
set -euo pipefail

folder=${1:?usage: pill-clip.sh <folder>}
color=(-vf "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p" -colorspace bt709 -color_primaries bt709 -color_trc bt709)
for frames in $folder/*(/); do
  name=${frames:t}
  ffmpeg -v error -y -framerate 30 -i $frames/%04d.png $color -c:v libx264 -preset slow -crf 18 -movflags +faststart -an \
    $folder/$name.mp4
  ffmpeg -v error -y -framerate 7.5 -i $frames/%04d.png $color -r 30 -c:v libx264 -preset slow -crf 18 -movflags +faststart \
    -an $folder/$name-quarter-speed.mp4
done
ls -l $folder
