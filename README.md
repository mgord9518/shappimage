# shImg (shappimage)

<p align="center"><img src="resources/shImg.svg" width=256 height="256"/></p>

A proof-of-concept implementation of AppImage created in shell script

## Why?

The idea just popped into my head as a way to make cross-architecture AppImages
so I decided to make it and see how feasible it is

## How does it work?
Overall it's pretty simple, the script checks if the user has squashfuse/dwarfs
binaries on their system (prefers this), if not it will extract a portable
binary to `$XDG_RUNTIME_DIR`. It then uses the binary to mount the attached
filesystem image at the specified offset, runs AppRun then unmounts and cleans
up once finished. See [File structure](#file-structure) for more info

## How different is it from standard AppImage?

Besides not being an ELF file, shImg has both semi-static and fully static
runtimes. This is to allow a smaller runtime size assuming the user has GLibC on
their system (most AppImages require it anyway). If an AppImage does not require
GLibC to run, it should use the fully static runtime, which can also run on
distros such as Alpine and NixOS. I imagine a tool made to build shImgs should
try to detect whether the application requires GLibC to run and use the
appropriate runtime. Some current issues shImg has that the standard AppImage
runtime doesn't are: shImg requires fuse3 and can only use `--appimage-extract`
on systems with a working FUSE driver. This may make it harder to use on minimal
or older systems.

The shImg runtime also has a longer initialization time compared to standard the
standard runtime. I've tried to optimize it a bit, but it still takes about
0.08s on my (fairly bad) hardware. I plan on adding a Perl section that should
hopefully speed up the parsing sections, further speeding it up. 0.08s is
negligible for GUI apps, but it may be significant for a CLI app running in a
loop or something the like. (mind you, Python 3 takes 0.1s on my system just to
initalize and make a print statement, so it probably won't hurt performance
that much for most things).

Another difference is the default compression being LZ4 (LZ4_HC) instead of LZIB,
I decided this because LZ4 compression is practically free while still getting
a decent (40%-60%) compression ratio. ZSTD is also supported as an option for
both mid and high compression at the cost of longer launch time, but it should
still be signifirantly faster than both ZLIB and  XZ. Larger apps quickly reveal
the benefit of using decompression optimized for modern hardware. Using LZ4, I
generally get apps 30%-50% larger than ZLIB, but the return is a near-native
launch speed.

## File structure

The shell script (with the help of some attached fuse binaries) do the same
job as the standard AppImage type 2 runtime, simply trying to find the image
offset as fast as possible, mount it and run the contained application inside
the SquashFS bundle. The (possibly multiarch) payload is appended, which
contains the app itself.

Finally, a zip archive is slapped on the end to serve as desktop integration
information. Zip was chosen over other formats for its ability to be placed at
an arbitrary offset and still be accessed, this allows desktop integration
software to simply open the AppImage as if it were a normal zip file, no need
to worry about what's going on up front.

```
╔═══════════════════════════════╗ ─╮
║          shell script         ║  │
╟─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─╢  │ ╭─────────╮
║ optionally gzipped squashfuse ║  ├─┤ runtime │
║ binaries  for  all  supported ║  │ ╰─────────╯
║ architectures                 ║  │
╟───────────────────────────────╢ ─┴╮
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║     SquashFS/DwarFS payload   ║   │ ╭───────────────────╮
║                               ║   ├─┤ meat and potatoes │
║     (LZ4_HC, ZSTD or GZIP)    ║   │ ╰───────────────────╯
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
║                               ║   │
╟───────────────────────────────╢ ─┬╯╭───────────────╮
║    desktop integration zip    ║  ├─┤ cherry on top │
╚═══════════════════════════════╝ ─╯ ╰───────────────╯
```

## Destop integration format

Inside the destop integration zip, the directory tree is as follows:
```
.APPIMAGE_RESOURCES/
.APPIMAGE_RESOURCES/destop_entry
.APPIMAGE_RESOURCES/metainfo     [OPTIONAL]
.APPIMAGE_RESOURCES/update_info  [OPTIONAL] [MUST BE UNCOMPRESSED]
.APPIMAGE_RESOURCES/signature    [OPTIONAL] [MUST BE UNCOMPRESSED]
.APPIMAGE_RESOURCES/icon/
.APPIMAGE_RESOURCES/icon/default.{png,svg}
.APPIMAGE_RESOURCES/icon/16.png  [OPTIONAL]
.APPIMAGE_RESOURCES/icon/24.png  [OPTIONAL]
.APPIMAGE_RESOURCES/icon/32.png  [OPTIONAL]
.APPIMAGE_RESOURCES/icon/48.png  [OPTIONAL]
.APPIMAGE_RESOURCES/icon/64.png  [OPTIONAL]
.APPIMAGE_RESOURCES/icon/128.png [OPTIONAL]
.APPIMAGE_RESOURCES/icon/256.png
.APPIMAGE_RESOURCES/icon/512.png [OPTIONAL]
```

`desktop_entry` contains the app's .desktop file. `metainfo` contains AppStream
metainfo, typically located at `usr/share/metainfo/*.appdata.xml`. `update_info`
contains AppImage update information, along with a special header and footer to
make it easy to find in shell script. `signature` is not yet impletmented, but
will be a GPG sig used for signing the shImg.

The only supported icon (`default.png`, `default.svg`) image formats are PNG
and SVG, and there should only be one "default" file. Thumbnailing images MUST
be PNG. 256.png is the only required image for thumbnailing, but more sizes may
also be added if desired.

## Building

To build the main shImg, first assemble an AppDir, the construction will be
nearly identical to standard AppImage, but in addition you may supply multiple
`AppRun` files to different architectures (eg: `AppRun` as the default,
presumably x86_64, then another called `AppRun.aarch64`, which will be called
on ARM64 systems). Second, compress the AppDir using SquashFS, currently
supported compression algorithms are LZ4 (recommended for small applications or
anything where speed is critical) ZSTD (recommended for larger applications or
where higher compression is desired) or GZIP (generally not recommended as
compression is both worse and slower than ZSTD). Lastly, append the SquashFS
image onto the appropriate runtime matching your desired architectures and
compression

At this point, the shImg should be a working application given that it's marked
executable or launched directly through the interpreter (eg: `sh ./app.shImg`)
but the desktop integration zip should also be applied as it'll make it easier
to integrate into the target system (once a final structure is decided on and
software is made to supoort it)

As for the desktop integration zip, its still extremely experimental so there
are no real tools to build. `add_integration.sh` is provided as an option to
apply the desktop integration zip on top of an existing shImg, but still very
much needs a cleaning up and is only tested in GH Actions. In order to use it,
use `./add_integration.zip [FULL PATH OF SHIMG]`. Given that it doesn't spout
an error, it should be added. To test, try extracting the shImg using the `zip`
command, the desktop integration info should be extracted into a directory
named `.APPIMAGE_RESOURCES`
