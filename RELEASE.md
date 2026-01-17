This release contains FFmpeg builds, compiled with MSVC (Microsoft Visual C++) via GitHub Actions, and organized as follows:

### ✨ Exclusive Feature: Advanced v360 "Rig Mode"

Unlike standard FFmpeg, this build includes a modified **`v360` filter** with a dedicated **Rig Mode (`input=tiles`)**. It is designed for high-fidelity panoramic stitching from arbitrary multi-camera setups, transforming multiple directional inputs into a seamless panoramic output (e.g., Equirectangular).

### Key Features:
* **Multi-Input Support**: Stitch any number of camera streams into a single panorama.
* **Seamless Blending**: Uses weighted inverse projection with **$C^2$-continuous Hermite interpolation (Smoothstep)** to eliminate visible seams.
* **Precise Alignment**: Individual **Pitch** and **Yaw** configuration for every input via the `cam_angles` option.
* **Frame-Accurate Sync**: Integrated `AVFrameSync` ensures all camera inputs remain perfectly synchronized during processing.
* **High Bit-Depth**: Full support for 8-bit and 16-bit processing pipelines.

> **For detailed technical documentation and source code, visit the project repository:**
> 👉 [**ffmpeg-v360-advanced**](https://github.com/artryazanov/ffmpeg-v360-advanced)

### Quick Example:
To stitch a 4-camera rig (Front, Right, Back, Left) into an Equirectangular panorama:

```bash
ffmpeg \
 -i cam0.mp4 -i cam1.mp4 -i cam2.mp4 -i cam3.mp4 \
 -filter_complex "
    [0:v][1:v][2:v][3:v] v360=input=tiles:output=equirect:
    cam_angles='0 0 0 90 0 180 0 270':
    rig_fov=90:blend_width=0.05
 " \
 output_panorama.mp4
```

### Build Configuration

- **Variants**: Includes both **shared** and **static** builds.
- **Architectures**: Each variant is available for **amd64**, **x86**, **arm**, and **arm64**.
- **Licenses**:
  - **GPL**: Includes GPL components such as the **x264** and **x265** encoders.
  - **LGPL**: Excludes GPL-licensed components.

#### Included Dependencies

- [nv-codec-headers](https://github.com/FFmpeg/nv-codec-headers.git)
- [zlib](https://github.com/madler/zlib.git)
- [libjxl](https://github.com/libjxl/libjxl.git)
  - [openexr](https://github.com/AcademySoftwareFoundation/openexr.git)
- [freetype](https://gitlab.freedesktop.org/freetype/freetype.git)
- [harfbuzz](https://github.com/harfbuzz/harfbuzz.git)
- [libass](https://github.com/libass/libass.git)
  - [fribidi](https://github.com/fribidi/fribidi.git)
- [SDL2](https://github.com/libsdl-org/SDL.git)
- [libvpx](https://github.com/webmproject/libvpx.git)
- [libwebp](https://github.com/webmproject/libwebp.git)
- [x264](https://code.videolan.org/videolan/x264.git) (GPL builds only)
- [x265](https://bitbucket.org/multicoreware/x265_git.git) (GPL builds only)

### Release Notes
