# shImg (shappimage)

<p align="center"><img src="resources/shImg.svg" width=256 height="256"/></p>

A proof-of-concept implementation of AppImage created in shell script

## Why?

The idea just popped into my head as a way to make cross-architecture AppImages so I decided to make it and see how feasible it is

## How does it work?

Overall it's pretty simple, the script checks if the user has squashfuse binaries on their system (prefers this), if not it will extract a portable squashfuse binary from inside the runtime to `/run/user/$UID/.shImg-squashfuse_$UID` or `$TMPDIR/.shImg-squashfuse_$UID` if $TMPDIR is set. It then uses squashfuse to mount the attached SquashFS image at the specified offset, running AppRun then unmounting and cleaning up once finished.

## How different is it from standard AppImage?

One of the biggest functional differences is probably the way the offset is found. In normal AppImages, which are ELF binaries, you can find the SquashFS offset by adding up all the ELF sections, but with shappimage it's simply set with the `sfsOffset` variable. This makes calculating it easier, but it also means that almost all existing AppImage libraries won't work with it, [`aisap`](github.com/mgord9518/aisap) being an exception, but only because I developed these 2 projects in tandum

Another one is that the normal AppImage runtime is statically linked, while shappimage dynamically links some libs. I decided to do this because an overwhelming majority of AppImages already require glibc and the runtime has to contain a copy of squashfuse for every supported archetecture. Statically compiling every compression lib and libc would very quickly blow up the runtime size

The runtime also has a longer initialization time compared to standard AppImage, I've tried to optimize it a bit, but it still takes about 0.08s on my (fairly bad) hardware. I plan on adding a Perl section that should hopefully speed up the parsing parts, further speeding it up. 0.08s is negligible for GUI apps, but it may be significant for a CLI app running in a loop or something the like. (mind you, Python 3 takes 0.1s on my system just to init and make a print statement, so it probably won't hurt performance that much for most things)

Another big difference is the default compression being LZ4 (LZ4_HC) instead of ZLIB, I decided this because LZ4 compression is practically free while still getting a decent (40%-60%) compression ratio. I'll probably end up supporting ZSTD as an option for both mid and high compression at the cost of longer launch time, but should still be faster than ZLIB and significantly faster than XZ. Using LZ4, I generally get apps 30%-50% larger than ZLIB, but large (50MB+) applications launch significantly faster, being nearly identical to their native counterparts
