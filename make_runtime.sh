#!/usr/bin/env bash

# VERY hacked together script just to assemble the runtime, probably will
# eventually make it cleaner, but it works for the time being

# ARCH variable sets the arch, COMP sets the compression algo
# Default to all supported architectures and LZ4 compression if unset
# TODO: Allow multiple compression algorithms in building
[ -z $ARCH ] && ARCH='x86_64-aarch64'
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

for arch in 'x86_64' 'aarch64' 'i386' 'armhf'; do
    # Download required squashfuse squashfusearies per architecture if they don't already
    # exist
    if [ $(grep "$arch" <<< "$ARCH") ]; then
        if [ ! -f "squashfuse/squashfuse.$arch"* ]; then
            wget "$squashfuse_source/squashfuse_${COMP}${static_prefix}.$arch" \
                -O "squashfuse/squashfuse.$arch"

            if [ $? -ne 0 ]; then
                rm "squashfuse/squashfuse.$arch"
                exit $?
            fi

        fi

        if [ $COMPRESS_SQUASHFUSE ]; then
            "$compress_command" $compress_flags "squashfuse/squashfuse.$arch"
            rm "squashfuse/squashfuse.$arch"
            bin_list="$bin_list squashfuse/squashfuse.$arch.gz"
        else
            bin_list="$bin_list squashfuse/squashfuse.$arch"
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


# Add one because this number is used by tail, which reads offsets off by 1
offset=$(($(cat runtime | wc -c) + 1))
length=0

# TODO: remove need for zero-padding
for bin in $bin_list; do
    offset=$(printf "%07d" $((10#$offset + 10#$length)))
    length=$(printf "%07d" $(wc -c ${bin}* | cut -d ' ' -f 1))

    arch=$(cut -d'.' -f2 <<< "$bin")

    sed -i "s/${arch}_offset=0000000/${arch}_offset=$offset/" runtime
    sed -i "s/${arch}_length=0000000/${arch}_length=$length/" runtime
done

runtime_size=$(cat runtime $bin_list | wc -c | tr -dc '0-9')

# Had to expand to 7 digits because of DwarFS's large size
image_offset=$(printf "%014d" "$runtime_size")
sed -i "s/=_IMAGE_OFFSET_/=$image_offset/" runtime

cat runtime $bin_list > runtime2

if [ ! $img_type = dwarfs ]; then
	mv runtime2 "runtime-$COMP$STATIC-$ARCH"
else
	mv runtime2 "runtime_dwarfs-static-$ARCH"
	rm squashfuse/squashfuse.x86_64.gz
fi

rm runtime
