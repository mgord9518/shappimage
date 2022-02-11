#!/bin/bash

# VERY hacked together script just to assemble the runtime, probably will
# eventually make it cleaner, but it works for the time being

# ARCH variable sets the arch, COMP sets the compression algo
# Default to all supported architectures and LZ4 compression if unset
# TODO: Allow multiple compression algorithms in building
[ -z $ARCH ] && ARCH='x86_64-aarch64-armhf'
[ -z $COMP ] && COMP='lz4'

[ ! -d 'squashfuse' ] && mkdir squashfuse

# Download required squashfuse squashfusearies per architecture if they don't already
# exist
if [[ "$ARCH" = *'x86_64'* ]]; then
	if [ ! -f 'squashfuse/squashfuse.x86_64' ]; then
		wget "https://github.com/mgord9518/portable_squashfuse/releases/download/nightly/squashfuse_ll_$COMP.x86_64" \
			-O squashfuse/squashfuse.x86_64
	fi
	[ -z $NO_COMPRESS_SQUASHFUSE ] && gzip -9n squashfuse/squashfuse.x86_64
else
	touch 'squashfuse/squashfuse.x86_64'
fi
if [[ "$ARCH" = *'aarch64'* ]]; then
	if [ ! -f 'squashfuse/squashfuse.aarch64' ]; then
		wget "https://github.com/mgord9518/portable_squashfuse/releases/download/manual/squashfuse_ll_$COMP.aarch64" \
			-O squashfuse/squashfuse.aarch64
	fi
	[ -z $NO_COMPRESS_SQUASHFUSE ] && gzip -9n squashfuse/squashfuse.aarch64
else
	touch 'squashfuse/squashfuse.aarch64'
fi
if [[ "$ARCH" = *'armhf'* ]]; then
	if [ ! -f 'squashfuse/squashfuse.armhf' ]; then
		wget "https://github.com/mgord9518/portable_squashfuse/releases/download/manual/squashfuse_ll_$COMP.armv7l" \
			-O squashfuse/squashfuse.armhf
	fi
	[ -z $NO_COMPRESS_SQUASHFUSE ] && gzip -9n squashfuse/squashfuse.armhf
else
	touch 'squashfuse/squashfuse.armhf'
fi

# Just for the time being as I don't have an x86 build yet
touch squashfuse/squashfuse.i386

# Collapse the script to make it smaller, not really sure whether I should keep
# it or not as it also obfuscates the code and the size difference makes little
# difference as the squashfuse binaries make up an overwhelming majority of the
# size of the runtime
echo '#!/bin/sh
#.shImg.#
#flattended script to reduce size; see <github.com/mgord9518/shappimage> for src' > runtime

[ -z $NO_COMPRESS_SQUASHFUSE ] && sed -i 's/head -c +$length > /head -c +$length | gzip -d > /' runtime
sed -i "s/=cmp/=$COMP/" runtime

# Experimental e x t r a flattening, might turn this into its own seperate application
cat runtime.sh | sed -e 's:#.*::' \
	-e 's/ \&\& /\&\&/g' \
	-e 's/ \&/\&/g' \
	-e 's/ || /||/g' \
	-e 's/ | /|/g' \
	-e 's/ {/{/g' \
	-e 's/; /;/g' \
	-e 's/ > />/g' \
	-e 's/> />/g' \
	-e 's/ < /</g' \
	-e 's/< /</g' \
	-e 's/ << /<</g' \
	-e 's/<< /<</g' \
	-e 's/ ()/()/g' \
	-e 's/cut -d /cut -d/g' \
	-e 's/head -c /head -c/g' \
	-e 's/tail -c /tail -c/g' \
	-e 's/-f /-f/g' \
	-e 's/-s /-s/g' \
	-e 's/-l /-l/g' \
	| tr -d '\t' | perl -0pe 's/;;\nesac/;;esac/g' | grep . >> runtime
#cat runtime.sh | sed -e 's:#.*::' | tr -d '\t' | grep . >> runtime

# Sizes of all files being packed into the runtime
_x64_l=$(printf "%06d" `wc -c squashfuse/squashfuse.x86_64* | cut -d ' ' -f 1`)
i386_l=$(printf "%06d" `wc -c squashfuse/squashfuse.i386* | cut -d ' ' -f 1`)
ar64_l=$(printf "%06d" `wc -c squashfuse/squashfuse.aarch64* | cut -d ' ' -f 1`)
ar32_l=$(printf "%06d" `wc -c squashfuse/squashfuse.armhf* | cut -d ' ' -f 1`)

# Offsets of squashfuse binaries by arch
# These are used when the runtime is executed to know where in the file to
# extract the appropriate binary
_x64_o=$(cat runtime | wc -c | tr -dc '0-9')
_x64_o=$(printf "%06d" $((10#$_x64_o + 1)))
i386_o=$(printf "%06d" $((10#$_x64_o + 10#$_x64_l)))
ar64_o=$(printf "%06d" $((10#$i386_o + 10#$i386_l)))
ar32_o=$(printf "%06d" $((10#$ar64_o + 10#$ar64_l)))

# Add in all the sizes and offsets
sed -i "s/_x64_o/$_x64_o/" runtime
sed -i "s/_x64_l/$_x64_l/" runtime

sed -i "s/i386_o/$i386_o/" runtime
sed -i "s/i386_l/$i386_l/" runtime

sed -i "s/ar64_o/$ar64_o/" runtime
sed -i "s/ar64_l/$ar64_l/" runtime

sed -i "s/ar32_o/$ar32_o/" runtime
sed -i "s/ar32_l/$ar32_l/" runtime

runLen=$(cat runtime squashfuse/squashfuse.* | wc -c | tr -dc '0-9')

# 6 digits long is enough for a 1MB runtime, which should be more than enough
# besides if everything is statically linked. If that is the case, it may be
# worth looking into compressing the squashfuse binaries as well, as they're
# cached anyway
sfsOffset=$(printf "%06d" "$runLen")
sed -i "s/_sfs_o/$sfsOffset/" runtime

cat runtime squashfuse/squashfuse.x86_64* squashfuse/squashfuse.i386* squashfuse/squashfuse.aarch64* squashfuse/squashfuse.armhf* > runtime2

#rm runtime
rm -r squashfuse
mv runtime2 "runtime-$COMP-$ARCH"
