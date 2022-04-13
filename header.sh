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

# Basic header informaion, While not going to be at a consistent file offset,
# it should be guarenteed to be very close to the top of the file (<20 lines
# when comments ane whitespace are stripped for easy accessing
img_type=_IMG_TYPE_
sfs_offset=_sfs_o_
version=0.2.0
COMP=cmp

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
