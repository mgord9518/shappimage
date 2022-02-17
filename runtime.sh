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
#   besides `mkruntime`, which is fully intended as a temporary builder for
#   testing the script development
# * Most AppImage integration software does not recognize the format as it
#   isn't standard and uses the sfs_offset variable as the offset instead of
#   the ELF header
# * Desktop integration information is stored in a zip file placed at the end
#   of the AppImage. This makes it trivial to extract and desktop integration
#   software won't even require a SquashFS driver. The update information can
#   even be extracted without zip! See the code under `--appimage-updateinfo`
#   flag to see how

# Run these startup commands concurrently to make them faster
[ -z $ARCH ] && ARCH=$(uname -m &)
# TODO: Add more ARMHF-compat arches
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

sfs_offset=_sfs_o
version=0.1.12
COMP=cmp
help_str='AppImage options:
  --appimage-extract          extract content from internal SquashFS image
  --appimage-help             print this help
  --appimage-mount            mount internal SquashFS to $MNTDIR, unmounting
                                after [RETURN] or [CTRL]+C is pressed
  --appimage-offset           print byte offset of internal SquashFS image
  --appimage-portable-home    create portable home directory to use as $HOME
  --appimage-portable-config  create portable config directory to use as 
                                $XDG_CONFIG_HOME
  --appimage-signature        print digital signature embedded in AppImage
  --appimage-updateinfo       print update info embedded in AppImage
  --appimage-version          print current version of shappimage runtime
 
enviornment variables:
  TMPDIR  the temporary directory for the AppImage
  MNTDIR  the mounting directory for the internal SquashFS image
 
unofficial AppImage runtime implemented in shell and squashfuse
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
			offset=_x64_o
			length=_x64_l;;
		i?86)
			offset=i386_o
			length=i386_l;;
		aarch64)
			offset=ar64_o
			length=ar64_l;;
		armhf)
			offset=ar32_o
			length=ar32_l;;
	esac

	if [ $length -eq 0 ]; then
		1>&2 echo "your machine architecture ($ARCH) is not supported in this bundle! :("
		exit 1
	fi

	# Set variable for random numbers if not available in running shell
	[ -z $RANDOM ] && RANDOM=$(tr -dc '0-9a-zA-Z' < /dev/urandom 2> /dev/null | head -c 8) &

	if [ "$use_bashisms" = "false" ]; then
		run_id="$(basename $TARGET_APPIMAGE | head -c 8)$RANDOM" &
	else
		run_id="$(basename $TARGET_APPIMAGE)"
		run_id="${run_id:0:8}$RANDOM"
	fi

	wait
	
	[ -z $MNTDIR ] && MNTDIR="$temp_dir/.mount_$run_id"

	# Ensure that the AppImage exits gracefully and unmounts before the script
	# exits
	trap 'unmount_appimage && exit 1' INT

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

	# If the user doesn't have squashfuse installed, extract the internal one
	command -v 'squashfuse' > /dev/null || extract_squashfuse

	# Attempt to mount and thow an error if unsuccessful
	squashfuse -o offset="$sfs_offset" "$TARGET_APPIMAGE" "$MNTDIR" 2> /dev/null
	if [ $? -ne 0 ]; then
		1>&2 echo "failed to mount SquashFS image! bundle may be corrupted :("
		exit 1
	fi
}

# Unmount prefering `fusermount` which is on practically all common desktop Linux
# distos, fall back on `umount` just in case
unmount_appimage() {
	[ -d "$TARGET_APPIMAGE" ] && return

	if command -v 'fusermount' > /dev/null; then
		fusermount -u "$MNTDIR" &
	else
		umount "$MNTDIR" &
	fi

	# Clean up all empty directories
	rmdir "$temp_dir/.mount"* 2> /dev/null &
}

# Find the location of the internal squashfuse binary based on system arch
extract_squashfuse() {
	temp_sqfuse="$temp_dir/shImg-sqfuse_$UID-$COMP"
	# Don't extract it again if it's already there
	if [ -x "$temp_sqfuse" ]; then
		squashfuse() {
			"$temp_sqfuse" "$@"
		}
		return
	fi

	# Extract it, mkruntime will modify this adding, a gzip extract into the
	# pipe if `$NO_COMPRESS_SQUASHFUSE` is unset
	tail -c +$offset "$0" | head -c +$length > "$temp_sqfuse" &
	chmod 0700 "$temp_sqfuse" &
	wait

	squashfuse() {
		"$temp_sqfuse" "$@"
	}
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
			cp -rv "$MNTDIR/"* "$MNTDIR/".* "$TARGET_APPIMAGE.appdir" | cut -d ' ' -f 3-
			unmount_appimage

			exit 0;;
		--appimage-help)
			echo "$help_str"
			exit 0;;
		--appimage-mount)
			mount_appimage
			echo "$MNTDIR"
			read REPLY
			unmount_appimage
			exit 0;;
		--appimage-offset)
			get_sfs_offset
			echo "$sfs_offset"
			exit 0;;
		--appimage-portable-home)
			mkdir "$0.home"
			if [ $? -ne 0 ]; then
				1>&2 echo "failed to create portable home! see error above"
				exit 1
			fi 
			echo "Created portable home at $0.home"
			exit 0;;
		--appimage-portable-config)
			mkdir "$0.config"
			if [ $? -ne 0 ]; then
				1>&2 echo "failed to create portable config! see error above"
				exit 1
			fi
			echo "created portable config at $0.config"
			exit 0;;
#		--appimage-signature)
#			;;
		--appimage-updateinfo)
			# Prefer `unzip` it showed to be the fastest with my tests
			if command -v 'unzip'; then
				unzip -p "$TARGET_APPIMAGE" '.APPIMAGE_RESOURCES/update_info' | head -n 1 | tail -n 1
			elif command -v 'bsdtar'; then
				bsdtar -Oxf "$TARGET_APPIMAGE" '.APPIMAGE_RESOURCES/update_info' | head -n 1 | tail -n 1
			else
				# L O N G sed one-liner to extract the update information from the
				# zip file placed at the end of the AppImage, this can be done
				# because it's one of the few files that doesn't get compressed and
				# has a special header and footer to make it easily locatable
				tac "$TARGET_APPIMAGE" | sed -n '/---END APPIMAGE \[update_info\]---/,/---BEGIN APPIMAGE \[update_info\]---/{ /---.* APPIMAGE \[update_info\]---/d; p }'
			fi
			exit 0;;
		--appimage-version)
			[ "$0" != "$TARGET_APPIMAGE" ] && version=$(get_var 'version')
			echo "$version"
			exit 0;;
		--appimage*)
			1>&2 echo "$i is not implemented in version $version of shappimage"
			exit 1;;
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
else
	if [ -f "$MNTDIR/AppRun" ]; then
		1>&2 echo "AppRun found but isn't executable! please report this error to the developers of this application"
	else 
		1>&2 echo "AppRun not found! please report this error to the developers of this application"
	fi
	unmount_appimage
	exit 1
fi

# Unmount when finished
unmount_appimage

# This script MUST end with an exit statement or the shell will continue
# trying to run binary bullshit as a script (not good)!
exit 0
