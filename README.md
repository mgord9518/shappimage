# shImg (shappimage)

A proof-of-concept implementation of AppImage created in shell script

## Why?

The idea just popped into my head as a way to make cross-archetecture AppImages so I decided to make it and see how feasible it is

## How does it work?

Overall it's pretty simple, the script checks if the user has squashfuse binaries on their system (prefers this), if not it will extract a portable squashfuse binary from inside the runtime to `/run/user/$UID/.shImg-squashfuse_$UID` or `$TMPDIR/.shImg-squashfuse_$UID` if $TMPDIR is set. It then uses squashfuse to mount the attached SquashFS image at the specified offset, running AppRun then unmounting and cleaning up once finished.

## How different is it from standard AppImage?

One of the biggest functional differences is probably the way the offset is found. In normal AppImages, which are ELF binaries, you can find the SquashFS offset by adding up all the sections, but with shappimage it's simply set with the `sfsOffset` variable.

Another one is that the normal AppImage runtime is statically linked, while shappimage dynamically links some libs. I decided to do this because an overwhelming majority of AppImages already require glibc and the runtime has to contain a copy of squashfuse for every supported archetecture. Statically compiling every compression lib and libc would very quickly blow up the runtime size

The default compression is LZ4 (LZ4_HC) instead of ZLIB, I decided this because LZ4 compression is practically free while still getting a decent (50%-60%) compression ratio. I'll probably end up supporting ZSTD as an option for both mid and high compression at the cost of longer launch time, but should still be faster than ZLIB and significantly faster than XZ
