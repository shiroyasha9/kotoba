#!/bin/zsh
# Encodes the hero demo's frames (`kotoba --hero-demo <folder>`, App/HeroDemoSnapshots.swift) for the site: for light
# and dark, a looping H.264 MP4 (every browser) and an AV1 WebM (smaller, where supported), muted, and the first frame as
# the poster (the chat's recording, which the video starts and ends on). The stage is a smooth gradient: in 8 bits the
# encoder codes its slow slopes as flat blocks, and in a scene change, where every frame differs a little from the last,
# it leaves the faded window's outline in them. The AV1 is 10-bit, which keeps the slopes (fewer bytes than 8-bit, too);
# browsers decode H.264 only in 8 bits, so it gets a lower CRF and aq-mode 3 (more bits to flat areas) instead.
# Each video stays under 0.65 MB (three scenes, about 10 s).
# Usage: scripts/hero-demo.sh <folder with light/ and dark/ frames>
set -euo pipefail

folder=${1:?usage: hero-demo.sh <folder>}
# sRGB frames to BT.709 video, tagged, so browsers show the colours of the poster.
tags=(-colorspace bt709 -color_primaries bt709 -color_trc bt709)
to709=scale=out_color_matrix=bt709:out_range=tv
for appearance in light dark; do
  frames=$folder/$appearance/%04d.png
  ffmpeg -v error -y -framerate 30 -i $frames -vf $to709,format=yuv420p $tags -c:v libx264 -preset veryslow -crf 21 \
    -x264-params aq-mode=3 -movflags +faststart -an $folder/hero-demo-$appearance.mp4
  ffmpeg -v error -y -framerate 30 -i $frames -vf $to709,format=yuv420p10le $tags -c:v libsvtav1 -preset 4 -crf 26 \
    -svtav1-params progress=0 -an $folder/hero-demo-$appearance.webm 2>/dev/null
  cp $folder/$appearance/0000.png $folder/hero-demo-$appearance.png
done
pngquant --quality 80-95 --speed 1 --strip --force --ext .png $folder/hero-demo-*.png
oxipng -o 4 --strip safe -q $folder/hero-demo-*.png
ls -l $folder/hero-demo-*
