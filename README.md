# shImg (shappimage)

<p align="center"><img src="resources/shImg.svg" width=256 height="256"/></p>

A proof-of-concept implementation of AppImage created in shell script

## Why?
The idea just popped into my head as a way to make cross-architecture AppImages
so I decided to make it and see how feasible it is

## How does it work?
Overall it's pretty simple, the script checks if the user has squashfuse
binaries on their system (prefers this), if not it will extract a portable
squashfuse binary to `$XDG_RUNTIME_DIR` It then uses squashfuse to mount the 
attached SquashFS image at the specified offset, running AppRun then unmount
and clean up once finished. See [File structure](#file-structure) for more info

## How different is it from standard AppImage?
A big one is that the normal AppImage runtime is statically linked, while
shappimage dynamically links some libs. I decided to do this because an
overwhelming majority of AppImages already require glibc and the runtime has to
contain a copy of squashfuse for every supported archetecture. Statically
compiling every compression lib and libc would very quickly blow up the runtime
size, but being that they're compressed by default now, that may not be a huge
issue. Both have their upsides and downsides. Static linking ensures maximum
portability but also can make the runtime quite large. Dynamic linking (core
libraries) gives a smaller runtime, but will be unable to run on very minimal
systems such as Alpine or any non-GLibC distros, which are commonly used for
Docker images

The runtime also has a longer initialization time compared to standard the
standard runtime. I've tried to optimize it a bit, but it still takes about
0.08s on my (fairly bad) hardware. I plan on adding a Perl section that should
hopefully speed up the parsing sections, further speeding it up. 0.08s is
negligible for GUI apps, but it may be significant for a CLI app running in a
loop or something the like. (mind you, Python 3 takes 0.1s on my system just to
initalize and make a print statement, so it probably won't hurt performance
that much for most things)

Difference is the default compression being LZ4 (LZ4_HC) instead of LZIB,
I decided this because LZ4 compression is practically free while still getting
a decent (40%-60%) compression ratio. ZSTD is also supported as an option for
both mid and high compression at the cost of longer launch time, but it should
still be faster than ZLIB and significantly faster than XZ. Larger apps quickly
reveal the benefit of using decompression optimized for modern hardware
Using LZ4, I generally get apps 30%-50% larger than ZLIB, but large (50MB+)
applications launch significantly faster than under ZLIB, being nearly identical
to their native counterparts.

## File structure
The shell script (with the help of some attached squashfuse binaries) do the
same job as the standard AppImage type 2 runtime, simply trying to find the
offset as fast as possible, mount it and run the contained application inside
the SquashFS bundle.

After, an identical (or possibly multi-arch) payload is
appended, allowing the AppImage to be run on mulpile CPU architectures at the
cost of a bigger bundle.

Finally, a zip archive is slapped on the end to serve as desktop integration
information. zip was chosen over other formats for its ability to be placed at
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
║        SquashFS payload       ║   │ ╭───────────────────╮
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

## Building

To build the main shImg, first assemble an AppDir, the construction should be
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
