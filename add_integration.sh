#!/bin/sh

# Script to add desktop integration to a partially assembled shImg

clean_exit() {
	rm -r '.APPIMAGE_RESOURCES' '.APPIMAGE_RESOURCES.zip' 2> /dev/null
	exit "$1"
}

# Make sure required tools are present
[ ! $(command -v zip) ]             && echo 'infozip is required to add and use shImg desktop integration!' && clean_exit 1
[ ! $(command -v rsvg-convert) ]    && echo 'rsvg-convert is required to convert icon!'                     && clean_exit 1

# Use oxipng if in GH Actions
if [ $GITHUB_ACTIONS ]; then
	wget -O - 'https://github.com/shssoichiro/oxipng/releases/download/v5.0.1/oxipng-5.0.1-x86_64-unknown-linux-musl.tar.gz' \
		| tar --strip-components 1 -xzvf -
fi

# Allow running as root without squashfuse for Docker/GH actions purposes,
# but don't suggest it because that's stupid
if [ ! $(command -v squashfuse) ] && [ $(id -u) -ne 0 ]; then
	echo 'squashfuse is required to add shImg desktop integration!'
	clean_exit 1
fi

# Give the resources their own directory
tempDir='./.APPIMAGE_RESOURCES'
helpStr="usage: $0 [shImg file] [appdir] [update info string]

this script is intended for use AFTER building your SquashFS image and
appending it to the appropriate shImg runtime, it will extract desktop
integration info from the SquashFS, integrating it into the zip footer
for easier extraction, along with update information

ONLY USE ON TRUSTED FILES
"

mkdir -p "$tempDir/icon"

# Add update info
# The begin and end lines are so the update info can be extracted without even
# needing zip installed. THIS IS ONLY TO BE DONE ON THE UPDATE INFORMATION, GPG
# SIG and a possible checksum

# If you have zip, simply extract the file, disregarding the first and final lines

# Here is a one-liner that can extract the update information using `tac` and `sed`:
# tac `file.AppImage` | sed -n '/---END APPIMAGE \[update_info\]---/,/-----BEGIN APPIMAGE \[update_info\]-----/{ /-----.* APPIMAGE \[update_info\]-----/d; p }'
[ "${#3}" -gt 0 ] && echo "---BEGIN APPIMAGE [update_info]---\n$3\n---END APPIMAGE [update_info]---"> "$tempDir/update_info"

# Copy first (should be only) desktop entry into what will be our zipped
# desktop integration
cp $(ls --color=never "$2"/*.desktop | head -n 1) "$tempDir/desktop_entry"
[ ! -f "$tempDir/desktop_entry" ] && echo 'no desktop entry found!' && clean_exit 1

# Same with icon, should only be one, remove extra if exists (prefer svg)
# default.* should be used to set the desktop entry icon, while 256.png should be
# used for thumbnailing
iconName=$(grep 'Icon=' "$tempDir/desktop_entry" | cut -d '=' -f 2-)
cp "$2/$iconName".png "$tempDir/icon/default.png"
cp "$2/$iconName".svg "$tempDir/icon/default.svg"
#optipng -o 7 -zm 9 -zs 3 "$tempDir/icon/default.png"
[ -f "$tempDir/icon.svg" ] && rm "$tempDir/icon/default.png"
./oxipng -o max -s -Z "$tempDir/icon/default.png" 2 > /dev/null

# Both check image validity and convert svg
[ -f "$tempDir/icon/default.png" ] && ln -s "default.png" "$tempDir/icon/256.png"
rsvg-convert -a -w 256 -h 256 "$2/$iconName.svg" -o "$tempDir/icon/256.png"
#optipng -o 7 -zm 9 -zs 3 "$tempDir/icon/256.png"
./oxipng -o max -s -Z "$tempDir/icon/256.png"
#[ $? -ne 0 ] && echo 'icon is invalid!' && clean_exit 1

cp '$2/usr/share/metainfo/'*.xml "$tempDir/metainfo"

# Do not compress GPG signature or update information as they both should be
# easy to extract as plain text
zip -r -n update_info '.APPIMAGE_RESOURCES.zip' '.APPIMAGE_RESOURCES'
cat '.APPIMAGE_RESOURCES.zip' >> "$1"
zip -A "$1"

clean_exit 0
