#!/bin/bash

# VERY hacked together script just to assemble the runtime, probably will
# eventually make it cleaner, but it works for the time being

# ARCH variable sets the arch, COMP sets the compression algo
# Default to all supported architectures and LZ4 compression if unset
# TODO: Allow multiple compression algorithms in building
[ -z $ARCH ] && ARCH='x86_64-aarch64-armhf'
[ -z $COMP ] && COMP='lz4'
[ -z $img_type ] && img_type='squashfs'

[ ! -d 'squashfuse' ] && mkdir squashfuse

# Download required squashfuse squashfusearies per architecture if they don't already
# exist
if [[ "$ARCH" = *'x86_64'* ]]; then
	if [ ! -f 'squashfuse/squashfuse.x86_64'* ]; then
		if [ $img_type = dwarfs ]; then
			wget "https://github.com/mhx/dwarfs/releases/download/v0.5.6/dwarfs-0.5.6-Linux.tar.xz" -O - | \
				tar -xOJ 'dwarfs-0.5.6-Linux/sbin/dwarfs' --strip=2 > squashfuse/squashfuse.x86_64
		else
			wget "https://github.com/mgord9518/portable_squashfuse/releases/download/nightly/squashfuse_ll_$COMP.x86_64" \
				-O squashfuse/squashfuse.x86_64
		fi
dd
	fi
	if [ $COMPRESS_SQUASHFUSE ]; then
		zopfli --i100 squashfuse/squashfuse.x86_64
		rm squashfuse/squashfuse.x86_64
		binList="squashfuse/squashfuse.x86_64.gz"
	else
		binList="squashfuse/squashfuse.x86_64"
	fi
fi
if [[ "$ARCH" = *'aarch64'* ]]; then
	if [ ! -f 'squashfuse/squashfuse.aarch64'* ]; then
		wget "https://github.com/mgord9518/portable_squashfuse/releases/download/manual/squashfuse_ll_$COMP.aarch64" \
			-O squashfuse/squashfuse.aarch64
	fi
	if [ $COMPRESS_SQUASHFUSE ]; then
		zopfli --i1000 squashfuse/squashfuse.aarch64
		rm squashfuse/squashfuse.aarch64
		binList="$binList squashfuse/squashfuse.aarch64.gz"
	else
		binList="$binList squashfuse/squashfuse.aarch64"
	fi
fi
if [[ "$ARCH" = *'armhf'* ]]; then
	if [ ! -f 'squashfuse/squashfuse.armhf'* ]; then
		wget "https://github.com/mgord9518/portable_squashfuse/releases/download/manual/squashfuse_ll_$COMP.armv7l" \
			-O squashfuse/squashfuse.armhf
	fi
	if [ $COMPRESS_SQUASHFUSE ]; then
		zopfli --i1000 squashfuse/squashfuse.armhf
		rm squashfuse/squashfuse.armhf
		binList="$binList squashfuse/squashfuse.armhf.gz"
	else
		binList="$binList squashfuse/squashfuse.armhf"
	fi
fi

# Collapse the script to make it smaller, not really sure whether I should keep
# it or not as it also obfuscates the code and the size difference makes little
# difference as the squashfuse binaries make up an overwhelming majority of the
# size of the runtime
echo '#!/bin/sh
#.shImg.#
#see<github.com/mgord9518/shappimage>4Src' > runtime

# Experimental e x t r a flattening, might turn this into its own seperate
# project
# this has really gotten out of hand
if [ $COMPRESS_SCRIPT ]; then
	perl bash_obfus.pl -i runtime.sh -o runtime.fus -V A
	echo 'alias A=alias
A B=else
A C=cut
A D="sed -e"
A E=echo
A F="command -v"
A G=grep
A H=head
A L=test
A I="if L"
A J="elif L"
A K=gzip
A M=mkdir
A N=then
A O="L -z"
A P="L -f"
A Q="I !"
A R="1>&2 E"
A S=sed
A T=tail
A U="E -ne"
A V=wait
A W="K -d"
A X=fi
A Y=exit
A Z=return
A A="xxd -s"' >> runtime
# ^ alias common commands and statements to single chars to drastically shrink
# scripts

	cat runtime.fus | tr -d '\t' | sed \
	-e 's/#.*//' \
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
	-e 's/cut -d /C -d/g' \
	-e 's/head -c /H -c/g' \
	-e 's/tail -c /T -c/g' \
	-e 's/^cut/C/g' \
	-e 's/|cut/|C/g' \
	-e 's/^head /H /g' \
	-e 's/|head/|H/g' \
	-e 's/^tail /T /g' \
	-e 's/|tail/|T/g' \
	-e 's/1>&2 echo/R/g' \
	-e 's/^echo -ne/U/g' \
	-e 's/^echo -en/U/g' \
	-e 's/^echo -e -n/U/g' \
	-e 's/^echo -n -e/U/g' \
	-e 's/^echo/E/g' \
	-e 's/\&\&echo -ne/\&\&U/g' \
	-e 's/\&\&echo -en/\&\&U/g' \
	-e 's/\&\&echo -e -n/\&\&U/g' \
	-e 's/\&\&echo -n -e/\&\&U/g' \
	-e 's/\&\&echo/\&\&E/g' \
	-e 's/^exit/Y/g' \
	-e 's/mkdir/M/g' \
	-e 's/sed -e/D/g' \
	-e 's/^sed/S/g' \
	-e 's/|sed/|S/g' \
	-e 's/xxd -s/A/g' \
	-e 's/xxd -e -s/A -e/g' \
	-e 's/command -v/F/g' \
	-e 's/gzip -d/W/g' \
	-e 's/gunzip/W/g' \
	-e 's/wait/V/g' \
	-e 's/gzip/K/g' \
	-e 's/grep/G/g' \
	-e 's/^elif \[/J/g' \
	-e 's/^if \[/I/g' \
	-e 's/^then/N/g' \
	-e 's/;then/;N/g' \
	-e 's/^else/B/g' \
	-e 's/^fi/X/g' \
	-e 's/^return/Z/g' \
	-e 's/\&\&return/\&\&Z/g' \
	-e 's/\[ /L /g' \
	-e 's/L -z/O/g' \
	-e 's/L -f/P/g' \
	-e 's/I !/Q/g' \
	-e 's/ \]//g' \
	| perl -0pe 's/;;\nesac/;;esac/g' | grep . >> runtime
else
	cat runtime.sh | tr -d '\t' | sed 's/#.*//' | grep . >> runtime
fi

cat header.sh main_funcs.sh > runtime

# Honestly, I can't think of any reason NOT to compress the squashfuse binaries
# but leaving it as optional anyway
[ $COMPRESS_SQUASHFUSE ] && sed -i 's/head -c +$length >/head -c +$length | gzip -d >/' runtime
sed -i "s/=cmp/=$COMP/" runtime
sed -i "s/=_IMG_TYPE_/=$img_type/" runtime

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

runLen=$(cat runtime $binList | wc -c | tr -dc '0-9')

# Had to expand to 7 digits because of DwarFS's large size
sfsOffset=$(printf "%07d" "$runLen")
sed -i "s/=_sfs_o_/=$sfsOffset/" runtime

cat runtime $binList > runtime2

#rm runtime
#rm -r squashfuse
if [ ! $img_type = dwarfs ]; then
	mv runtime2 "runtime-$COMP-$ARCH"
else
	mv runtime2 "runtime_dwarf-$ARCH"
	rm squashfuse/squashfuse.x86_64.gz
fi
