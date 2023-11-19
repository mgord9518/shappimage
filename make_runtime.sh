#!/usr/bin/env bash

# VERY hacked together script just to assemble the runtime, probably will
# eventually make it cleaner, but it works for the time being

# ARCH variable sets the arch, COMP sets the compression algo
# Default to all supported architectures and LZ4 compression if unset
# TODO: Allow multiple compression algorithms in building
[ -z $ARCH ] && ARCH='x86_64-aarch64-armhf'
[ -z $COMP ] && COMP='lz4'
[ -z $img_type ] && img_type='squashfs'

[ $STATIC_SQUASHFUSE ] && static_prefix='.static'

squashfuse_source="https://github.com/mgord9518/squashfuse-zig/releases/download/continuous"

[ ! -d 'squashfuse' ] && mkdir squashfuse

if command -v zopfli > /dev/null; then
    compress_command=zopfli
    compress_flags="--i100"
else
    compress_command=gzip
    compress_flags="-9"
fi

for arch in 'x86_64' 'aarch64' 'x86' 'armhf'; do
    # Download required squashfuse squashfusearies per architecture if they don't already
    # exist
    if [ $(grep "$arch" <<< "$ARCH") ]; then
        if [ ! -f "squashfuse/squashfuse.$arch"* ]; then
            wget "$squashfuse_source/squashfuse_${COMP}${static_prefix}.$arch" \
                -O "squashfuse/squashfuse.$arch"
        fi

        if [ $COMPRESS_SQUASHFUSE ]; then
            "$compress_command" $compress_flags "squashfuse/squashfuse.$arch"
            rm "squashfuse/squashfuse.$arch"
            binList="$binList squashfuse/squashfuse.$arch.gz"
        else
            binList="$binList squashfuse/squashfuse.$arch"
        fi
    fi
done

# Collapse the script to make it smaller, not really sure whether I should keep
# it or not as it also obfuscates the code and the size difference makes little
# difference as the squashfuse binaries make up an overwhelming majority of the
# size of the runtime
echo '#!/bin/sh
#.shImg.#
#see <github.com/mgord9518/shappimage> for src' > runtime

cat runtime.sh | tr -d '\t' | sed 's/#.*//' | grep . >> runtime

arch=$(echo "$ARCH" | tr '-' ';')

# Honestly, I can't think of any reason NOT to compress the squashfuse binaries
# but leaving it as optional anyway
[ $COMPRESS_SQUASHFUSE ] && sed -i 's/head -c $length >/head -c $length | gzip -d >/' runtime
sed -i "s/=_IMAGE_COMPRESSION_/=$COMP/" runtime
sed -i "s/=_IMAGE_TYPE_/=$img_type/" runtime
sed -i "s/=_ARCH_/='$arch'/" runtime

# Sizes of all files being packed into the runtime
_x64_l=$(printf "%07d" `wc -c squashfuse/squashfuse.x86_64* | cut -d ' ' -f 1`)
i386_l=$(printf "%07d" `wc -c squashfuse/squashfuse.i386* | cut -d ' ' -f 1`)
ar64_l=$(printf "%07d" `wc -c squashfuse/squashfuse.aarch64* | cut -d ' ' -f 1`)
ar32_l=$(printf "%07d" `wc -c squashfuse/squashfuse.armhf* | cut -d ' ' -f 1`)

# Offsets of squashfuse binaries by arch
# These are used when the runtime is executed to know where in the file to
# extract the appropriate binary
_x64_o=$(cat runtime | wc -c | tr -dc '0-9')
_x64_o=$(printf "%07d" $((10#$_x64_o + 1)))
i386_o=$(printf "%07d" $((10#$_x64_o + 10#$_x64_l)))
ar64_o=$(printf "%07d" $((10#$i386_o + 10#$i386_l)))
ar32_o=$(printf "%07d" $((10#$ar64_o + 10#$ar64_l)))

# Add in all the sizes and offsets
sed -i "s/=_x64_o_/=$_x64_o/" runtime
sed -i "s/=_x64_l_/=$_x64_l/" runtime

sed -i "s/=i386_o_/=$i386_o/" runtime
sed -i "s/=i386_l_/=$i386_l/" runtime

sed -i "s/=ar64_o_/=$ar64_o/" runtime
sed -i "s/=ar64_l_/=$ar64_l/" runtime

sed -i "s/=ar32_o_/=$ar32_o/" runtime
sed -i "s/=ar32_l_/=$ar32_l/" runtime

runtime_size=$(cat runtime $binList | wc -c | tr -dc '0-9')

# Had to expand to 7 digits because of DwarFS's large size
image_offset=$(printf "%014d" "$runtime_size")
sed -i "s/=_IMAGE_OFFSET_/=$image_offset/" runtime

cat runtime $binList > runtime2

if [ ! $img_type = dwarfs ]; then
	mv runtime2 "runtime-$COMP$STATIC-$ARCH"
else
	mv runtime2 "runtime_dwarfs-static-$ARCH"
	rm squashfuse/squashfuse.x86_64.gz
fi
