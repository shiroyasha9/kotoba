#!/bin/zsh
# Encodes the hero demo's frames (`kotoba --hero-demo <folder>`, App/HeroDemoSnapshots.swift) for the site: for light
# and dark, a looping AV1 WebM (Chrome, Firefox, Safari with AV1), an HEVC MP4 (Safari on Macs without AV1), an H.264
# MP4 (everything else), muted, and the first frame as the poster (the chat's recording, which the video starts and ends
# on). The stage is a smooth gradient: in 8 bits the encoder codes its slow slopes as flat blocks, and in a scene
# change, where every frame differs a little from the last, it leaves the faded window's outline in them. So AV1 and
# HEVC are 10-bit, which keeps the slopes (fewer bytes than 8-bit, too); browsers decode H.264 only in 8 bits, so it
# gets a lower CRF and aq-mode 3 (more bits to flat areas) instead. Each video stays under 0.65 MB (about 10 s).
# Usage: scripts/hero-demo.sh <folder with light/ and dark/ frames>
set -euo pipefail

folder=${1:?usage: hero-demo.sh <folder>}
# The frames are sRGB (the app draws them in sRGB): BT.709 primaries, the sRGB curve. The video keeps both and says so,
# with the BT.709 matrix in TV range, so a browser shows the poster's colours: Safari draws a stream tagged with the
# BT.709 curve about 3% lighter than the poster.
tags=(-colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv)
to709=scale=out_color_matrix=bt709:out_range=tv
for appearance in light dark; do
  frames=$folder/$appearance/%04d.png
  out=$folder/hero-demo-$appearance
  ffmpeg -v error -y -framerate 30 -i $frames -vf $to709,format=yuv420p10le $tags -c:v libsvtav1 -preset 4 -crf 26 \
    -svtav1-params progress=0 -an $out.webm 2>/dev/null
  # x265's psy-rd keeps a block's texture over its exact value: in a fade-out it kept the faded text on the bare stage.
  ffmpeg -v error -y -framerate 30 -i $frames -vf $to709,format=yuv420p10le $tags -c:v libx265 -preset slow -crf 18 \
    -x265-params log-level=error:psy-rd=0:psy-rdoq=0 -tag:v hvc1 -movflags +faststart -an $out-hevc.mp4
  ffmpeg -v error -y -framerate 30 -i $frames -vf $to709,format=yuv420p $tags -c:v libx264 -preset veryslow -crf 21 \
    -x264-params aq-mode=3 -movflags +faststart -an $out.mp4
  cp $folder/$appearance/0000.png $folder/hero-demo-$appearance.png
done
pngquant --quality 80-95 --speed 1 --strip --force --ext .png $folder/hero-demo-*.png
oxipng -o 4 --strip safe -q $folder/hero-demo-*.png
ls -l $folder/hero-demo-*
