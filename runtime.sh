#!/bin/sh
#.shImg.#

# Copyright © 2021-2022 Mathew Gordon <github.com/mgord9518>

# This is a proof-of-concept of a fat AppImage runtime using shell scripting
# The base functionality is mostly modeled directly off of AppImage type 2's
# `runtime.c` but there are some differences.
#
# * Addition of $MNTDIR, which allows setting the location of where to mount
#   the SquashFS archive
# * Mounts into `/run` instead of `/tmp`, unless `$TMPDIR` is set. I can't
#   imagine this would change functionality hardly at all, but I guess it's
#   worth mentioning
# * Can support multiple architectures with one AppImage, may be good for small
#   programs
# * Slower launch time (obviously, it's shell vs C). The launch difference is
#   negligible for GUI apps, but may make a significant difference when running
#   a CLI program many times. The launch time impact can also be remedied by
#   LZ4 compression (default) at the cost of larger bundles. IMO, it is a good
#   balance between launch time and compression. This script also runs faster
#   with dash compared to bash or zsh
# * There are currently no tools to properly build AppImages with this runtime
#   besides `make_runtime.sh`, which is fully intended as a temporary builder
#   for testing the script development
# * Most AppImage integration software does not recognize the format as it
#   isn't standard and uses the sfs_offset variable as the offset instead of
#   the ELF header. aisap <github.com/mgord9518/aisap> is designed to read
#   them though, maybe I should make a libappimage-compatible binding in order
#   to make it a simple drop-in replaceent for apps that rely on it
# * Desktop integration information is stored in a zip file placed at the end
#   of the bundle. This makes it trivial to extract and desktop integration
#   software won't even require a SquashFS driver. The update information can
#   even be extracted without zip! See the code under `--appimage-updateinfo`
#   flag to see how

# TODO:
# * Make `--appimage-extract` work without fuse
# * Use a patched version of fuse in the portable squashfuse so that fuse2 and
#   fuse3 systems can run shImgs (this was recently fixed in the upstream
#   AppImage runtime)

# Basic header informaion, While not going to be at a consistent file offset,
# it should be guarenteed to be very close to the top of the file (<20 lines
# when comments ane whitespace are stripped for easy accessing
img_type=_IMG_TYPE_
sfs_offset=_sfs_o_
version=0.2.2
arch=_ARCH_
COMP=cmp

# Run these startup commands concurrently to make them faster
[ -z $ARCH ] && ARCH=$(uname -m &)
[ -z $UID  ] && UID=$(id -u &)
[ -z $TARGET_APPIMAGE ] && TARGET_APPIMAGE="$0"
shell=$(readlink "/proc/$$/exe" &)

wait

if [ $TMPDIR ]; then
	temp_dir="$TMPDIR"
elif [ -w "$XDG_RUNTIME_DIR" ]; then
	temp_dir="$XDG_RUNTIME_DIR"
else
	temp_dir="/tmp"
fi
# TODO: Add more ARMHF-compat arches
if [ "$ARCH" = armv7l ]; then
	ARCH=armhf
fi
case "$shell" in
	*bash)
		use_bashisms=true;;
	*osh)
		use_bashisms=true;;
	*zsh)
		use_bashisms=true;;
	*)
		use_bashisms=false;;
esac

help_str='AppImage options:
  --appimage-extract          extract content from internal image
  --appimage-help             print this help
  --appimage-mount            mount internal image to $MNTDIR, unmounting
                                after [RETURN] or [CTRL]+C is pressed
  --appimage-offset           print byte offset of internal image
  --appimage-portable-home    create portable home directory to use as $HOME
  --appimage-portable-config  create portable config directory to use as 
                                $XDG_CONFIG_HOME
  --appimage-signature        print digital signature embedded in AppImage
  --appimage-updateinfo       print update info embedded in AppImage
  --appimage-version          print current version of shImg runtime
 
enviornment variables:
  TMPDIR  the temporary directory for the AppImage
  MNTDIR  the mounting directory for the internal image
 
unofficial AppImage runtime implemented in shell script
'
# Calculate ELF size in pure shell using `shnum * shentsize + shoff`
# Most of this code is just to find their values
get_sfs_offset() {
	[ "$0" = "$TARGET_APPIMAGE" ] && return

	elf_endianness=$(xxd -s 5 -l 1 -p "$TARGET_APPIMAGE" &)
	elf_class=$(xxd -s 4 -l 1 -p "$TARGET_APPIMAGE" &)
	wait
	
#	if [ "$use_bashisms" = 'true' ]; then
#		get_sfs_offset_bashisms
#		return
#	fi

	# How to interpret the bytes based on their endianness
	# 0x01 is little, 0x02 is big, 0x6e is shappimage
	if [ "$elf_endianness" = '01' ]; then
		get_bytes() {
			xxd -e -s "$1" -l "$2" -g "$2" "$TARGET_APPIMAGE" | cut -d ' ' -f 2
		}
	elif [ "$elf_endianness" = '02' ] || [ "$elf_endianness" = '6e' ]; then
		get_bytes() {
			xxd -s "$1" -l "$2" -p $TARGET_APPIMAGE 
		}
	else
		1>&2 echo "invalid endianness (0x$elf_endianness), unable to find offset!"
		exit 1
	fi

	# 32 bit is 0x01, 64 bit is 0x02, shappimage is 0x69 (nice)
	if [ "$elf_class" = "01" ]; then
		shentsize='0x'$(get_bytes 46 2 &)
		shnum='0x'$(get_bytes 48 2 &)
		shoff='0x'$(get_bytes 32 4 &)
	elif [ "$elf_class" = "02" ]; then
		shentsize='0x'$(get_bytes 58 2 &)
		shnum='0x'$(get_bytes 60 2 &)
		shoff='0x'$(get_bytes 40 8 &)
	elif [ "$elf_class" = "69" ]; then
		sfs_offset=$(get_var 'sfs_offset')
		return
	fi

	wait

	sfs_offset=$(($shnum*$shentsize+$shoff))
}

# WIP -- attempt to utilize "bashisms" to speed up the script for shells that
# can have them.
#get_sfs_offset_bashisms() {
#	if [ "$elf_endianness" = '01' ]; then
#		header=$(xxd -e -s 4 -l 70 -g 16 "$TARGET_APPIMAGE" | cut -d ' ' -f 2)
#		elf_class=${header:30:2}
#		if [ "$elf_class" = "01" ]; then
#			shentsize='0x'${header:74:4}
#			shnum='0x'${header:70:4}
#			shoff='0x'${header:33:8}
#		elif [ "$elf_class" = "02" ]; then
#			shentsize='0x'${header:132:4}
#			shnum='0x'${header:136:4}
#			shoff='0x'${header:74:16}
#		fi
#		# Doesn't support big endianness yet, but that is very rare on modern
#		# processors anyway
#	elif [ "$elf_endianness" = '02' ] || [ "$elf_endianness" = '6e' ]; then
#		header=$(xxd -s 4 -l 58 -p "$TARGET_APPIMAGE")
#		elf_class=${header:0:2}
##		if [ "$elf_class" = "01" ]; then
##			shentsize='0x'${header:74:4}
##			shnum='0x'${header:70:4}
##			shoff='0x'${header:33:8}
##		elif [ "$elf_class" = "02" ]; then
##			shentsize='0x'${header:132:4}
##			shnum='0x'${header:136:4}
##			shoff='0x'${header:74:16}
##		fi
#		if [ "$elf_class" = "02" ]; then
#			shentsize='0x'${header:132:4}
#			shnum='0x'${header:136:4}
#			shoff='0x'${header:74:16}
#		fi
#	else
#		1>&2 echo "invalid endianness (0x$elf_endianness), unable to find offset!"
#		exit 1
#	fi
#
#	# Get offset for another shappimage
#	if [ "$elf_class" = "69" ]; then
#		sfs_offset=$(get_var 'sfs_offset')
#		return
#	fi
#
#	sfs_offset=$(($shnum*$shentsize+$shoff))
#}

# Mount the SquashFS image either using squashfuse on the host system or by
# extracting an internal squashfuse binary.
mount_appimage() {
	# If AppDir instead of AppImage, return quickly
	if [ -d "$TARGET_APPIMAGE" ] && [ -x "$TARGET_APPIMAGE/AppRun" ]; then
		MNTDIR="$TARGET_APPIMAGE"
		return
	fi

	case "$ARCH" in
	x86_64)
		offset=_x64_o_
		length=_x64_l_
		;;
	i?86)
		offset=i386_o_
		length=i386_l_
		;;
	aarch64)
		offset=ar64_o_
		length=ar64_l_
		;;
	armhf)
		offset=ar32_o_
		length=ar32_l_
		;;
	*)
		1>&2 echo "your machine architecture ($ARCH) is not supported by shImg version $version"
		exit 1
		;;
	esac

	if [ $length -eq 0 ]; then
		1>&2 echo "your machine architecture ($ARCH) is not supported in this bundle! :("
		exit 1
	fi

	# Set variable for random numbers if not available in running shell
	[ -z $RANDOM ] && RANDOM=$(tr -dc '0-9a-zA-Z' < /dev/urandom 2> /dev/null | head -c 8)

	if [ "$use_bashisms" = "false" ]; then
		run_id="$(basename $TARGET_APPIMAGE | head -c 8)$RANDOM"
	else
		run_id="$(basename $TARGET_APPIMAGE)"
		run_id="${run_id:0:8}$RANDOM"
	fi

	[ -z $MNTDIR ] && MNTDIR="$temp_dir/.mount_$run_id"

	# Ensure that the AppImage exits gracefully and unmounts before the script
	# exits
	trap 'unmount_appimage 1' INT

	# Create the temporary and mounting directories if they don't exist
	if [ ! -d "$temp_dir" ] && [ -w "$temp_dir/.." ]; then
		mkdir -p "$temp_dir"
	elif [ ! -d "$temp_dir" ] && [ ! -w "$temp_dir/.." ]; then
		1>&2 echo "cannot create temporary directory $temp_dir! parent directory not writable!"
	fi

	if [ ! -d "$MNTDIR" ] && [ -w "$temp_dir" ]; then
		mkdir -p "$MNTDIR"
	elif [ ! -w "$temp_dir" ]; then
		1>&2 echo "failed to create mount dir! $temp_dir not writable!"
		exit 1
	fi

	get_sfs_offset
	extract_exe

	# Attempt to mount and thow an error if unsuccessful
		mnt_cmd "$TARGET_APPIMAGE" "$MNTDIR" $sfs_offset
	if [ $? -ne 0 ]; then
		1>&2 echo "failed to mount bundle image! see error message above"
		exit 1
	fi
}

# Unmount and exit, prefering `fusermount` which is on practically all common 
# desktop Linux distos, fall back on `umount` just in case
# Lazy unmount is to fix "resource busy" problem when running on Ubuntu 18,04
unmount_appimage() {
	[ -d "$TARGET_APPIMAGE" ] && return

	if command -v 'fusermount' > /dev/null; then
		fusermount -uz "$MNTDIR" &
	else
		umount -l "$MNTDIR" &
	fi

	# Clean up all empty directories
	rmdir "$temp_dir/.mount"* 2> /dev/null &

	exit $1
}

# Find the location of the internal binary (may be either squashfuse or DwarFS)
# based on system arch
extract_exe() {
	temp_exe="$temp_dir/shImg-${img_type}_$UID-$COMP"

	if [ "$img_type" = 'squashfs' ]; then
		command -v 'squashfuse' > /dev/null && temp_exe=$(command -v 'squashfuse')
		mnt_cmd() {
			"$temp_exe" "$1" "$2" -o offset=$3
		}
	elif [ "$img_type" = 'dwarfs' ]; then
		command -v 'dwarfs' > /dev/null && temp_exe=$(command -v 'dwarfs')
		mnt_cmd() {
			"$temp_exe" "$1" "$2" -o offset=$3 -o debuglevel=error
		}
	fi

	# Don't extract it again if it's already there
	if [ -x "$temp_exe" ]; then
		return
	fi

	# Extract it, mkruntime will modify this adding, a gzip extract into the
	# pipe if `$NO_COMPRESS_SQUASHFUSE` is unset
	tail -c +$offset "$0" | head -c +$length > "$temp_exe" &
	chmod 0700 "$temp_exe" &
	wait
}

get_var() {
	grep -a -m 1 "$1=" "$TARGET_APPIMAGE" | cut -d '=' -f 2-
}

# Handle AppImage-specific args (modeled after type 2 AppImage runtime)
for i in "$@"; do
	case "$i" in
	--appimage-extract)
		echo "Extracting"
		if [ ! -d "$TARGET_APPIMAGE.appdir" ]; then
			mkdir "$TARGET_APPIMAGE.appdir"
			if [ $? -ne 0 ]; then
				1>&2 echo "failed to create extraction directory! see error above"
				exit 1
			fi
		elif [ ! -w "$TARGET_APPIMAGE.appdir" ]; then
			1>&2 echo "extraction directory ($TARGET_APPIMAGE.appdir) isn't writable!"
			exit 1
		fi

		mount_appimage
		cp -rv "$MNTDIR/." "$TARGET_APPIMAGE.appdir" | cut -d ' ' -f 3-
		unmount_appimage 0
		;;
	--appimage-help)
		echo "$help_str"
		exit 0;;
	--appimage-mount)
		mount_appimage
		echo "$MNTDIR"
		read REPLY
		unmount_appimage 0
		;;
	--appimage-offset)
		get_sfs_offset
		echo "$sfs_offset"
		exit 0
		;;
	--appimage-portable-home)
		mkdir "$0.home"
		if [ $? -ne 0 ]; then
			1>&2 echo "failed to create portable home! see error above"
			exit 1
		fi 
		echo "Created portable home at $0.home"
		exit 0
		;;
	--appimage-portable-config)
		mkdir "$0.config"
		if [ $? -ne 0 ]; then
			1>&2 echo "failed to create portable config! see error above"
			exit 1
		fi
		echo "created portable config at $0.config"
		exit 0
		;;
#	--appimage-signature)
#		;;
	--appimage-updateinfo)
	# Prefer `unzip` it showed to be the fastest with my tests
		if command -v 'unzip' > /dev/null; then
			unzip -p "$TARGET_APPIMAGE" '.APPIMAGE_RESOURCES/update_info' | head -n 2 | tail -n 1
		elif command -v 'bsdtar' > /dev/null; then
			bsdtar -Oxf "$TARGET_APPIMAGE" '.APPIMAGE_RESOURCES/update_info' | head -n 2 | tail -n 1
		else
			# L O N G sed one-liner to extract the update information from the
			# zip file placed at the end of the AppImage, this can be done
			# because it's one of the few files that doesn't get compressed and
			# has a special header and footer to make it easily locatable
			tac "$TARGET_APPIMAGE" | sed -n '/---END APPIMAGE \[update_info\]---/,/---BEGIN APPIMAGE \[update_info\]---/{ /---.* APPIMAGE \[update_info\]---/d; p }'
		fi
		exit 0
		;;
	--appimage-version)
		[ "$0" != "$TARGET_APPIMAGE" ] && version=$(get_var 'version')
		echo "$version"
		exit 0
		;;
	--appimage*)
		1>&2 echo "$i is not implemented in version $version of shImg"
		exit 1
		;;
	esac
done

# Done setting up, proceed to executing if no arguments are given
mount_appimage

if [ -d "$TARGET_APPIMAGE.home" ]; then
	echo "setting \$HOME to $TARGET_APPIMAGE.home"
	export HOME="$(realpath $TARGET_APPIMAGE.home)"
fi

if [ -d "$TARGET_APPIMAGE.config" ]; then
	echo "setting \$XDG_CONFIG_HOME to $TARGET_APPIMAGE.config"
	export XDG_CONFIG_HOME="$(realpath $TARGET_APPIMAGE.config)"
fi

export ARGV0="$TARGET_APPIMAGE" 
export APPDIR="$MNTDIR" 
export APPIMAGE="$TARGET_APPIMAGE" 

# Run the AppRun script/binary, preferring one provided for the specific arch
# if provided
if [ -x "$MNTDIR/AppRun.$ARCH" ]; then
        "$MNTDIR/AppRun.$ARCH" "$@"
elif [ -x "$MNTDIR/AppRun" ]; then
        "$MNTDIR/AppRun" "$@"
elif [ -f "$MNTDIR/AppRun" ]; then
        1>&2 echo "AppRun found but isn't executable! please report this error to the developers of this application"
        # Exit in subshell to set $? variable
        (exit 1)
else
        1>&2 echo "AppRun not found! please report this error to the developers of this application"
        (exit 1)
fi

# Unmount when finished
unmount_appimage $?
