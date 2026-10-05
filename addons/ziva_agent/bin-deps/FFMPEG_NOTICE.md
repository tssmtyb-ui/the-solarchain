# FFmpeg in Ziva

Ziva Devlog runs `bin-deps/<platform>/ffmpeg` to record game runs and make videos. It is FFmpeg
9.0.2, built from the unmodified release at https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz with
only LGPL-compatible options, and is licensed under the GNU Lesser General Public License version
2.1 or later: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

It contains these libraries, each under its own license:

- OpenH264 2.6.0, BSD-2-Clause: https://github.com/cisco/openh264
- libvpx 1.17.0, BSD-3-Clause: https://github.com/webmproject/libvpx
- FreeType 2.14.3, FreeType License: https://freetype.org
- HarfBuzz 14.5.0, MIT: https://github.com/harfbuzz/harfbuzz

Its configuration enables only the demuxers, decoders, encoders, filters and muxers Devlog uses,
and no GPL or nonfree component. Write to license@ziva.sh for the exact build script.
