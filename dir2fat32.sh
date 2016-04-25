#!/bin/bash

# Create a FAT32 disk image from the contents of a directory.
#
# This tool requires the following to be available on the host system:
#
# - util-linux
# - dosfstools
# - mtools
#
# Copyright 2016 Outernet Inc
# Some rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>
#

set -e

VERSION=3.0a1

SECTOR_SIZE=512
LOGICAL_SECTOR_SIZE=512
NEW_DISKLABEL=o
NEW_PARTITION=n
PRIMARY=p
FIRST=1
OFFSET_8MB=16384
SET_PARTITION_TYPE=t
WIN95_FAT32=b
WRITE=w
VALID_SECSIZES=( 512 1024 2048 4096 8912 16384 32768 )

usage() {
  echo "Usage: $(basename $0) [-h -f -S SECSIZE] OUTPUT SIZE SOURCE"
  echo
  echo "Arguments:"
  echo "  OUTPUT      name of the image file"
  echo "  SIZE        size of the FAT32 partition in MiB (1024 based)"
  echo "  SOURCE      source directory"
  echo
  echo "Options:"
  echo "  -S SECSIZE  logical sector size (default: 512)"
  echo "  -f          overwrite existing image file (if any)"
  echo "  -h          show this message and exit"
  echo
  echo "Valid values for SECSIZE are: 512, 1024, 2048, 4096, 8912, 16384, and "
  echo "32768. Using values other than those will result in an error."
  echo
  echo "NOTE: the image size is always 8 MiB larger than the partition size"
  echo "to account for the partition offset. The partition size itself should"
  echo "ideally be a multiple of 8 MiB."
  echo
  echo "dir2fat32 v$VERSION"
  echo "Copyright 2016 Outernet Inc"
  echo "Some rights reserved."
  echo
  echo "This program is free software released under GNU GPLv3 license."
  echo "See <http://www.gnu.org/licenses/> for more information."
  echo
}

test_secsize() {
  secsize=$1
  for s in ${VALID_SECSIZES[@]}; do
    if [ "$s" == $secsize ]; then
      return 1
    fi
  done
  return 0
}

relpath() {
  full=$1
  if [ "$full" == "$SOURCE" ]; then
    echo ""
  else
    base=${SOURCE%%/}/
    echo "${full##$base}"
  fi
}

disksize() {
  echo $(expr 8 + $SIZE)
}

filesize() {
  path=$1
  echo $(expr $(stat -c%s "$path") / 1024 / 1024) MiB
}

mkcontainer() {
  fallocate -l ${DISK_SIZE}M "$OUTPUT"
  echo "$NEW_DISKLABEL
$NEW_PARTITION
$PRIMARY
$FIRST
$OFFSET_8MB

$SET_PARTITION_TYPE
$WIN95_FAT32
$WRITE
" | fdisk "$OUTPUT" >/dev/null
}

mkpartition() {
  fallocate -l ${SIZE}M "$PARTITION"
  mkfs.fat -F32 -S"$LOGICAL_SECTOR_SIZE" "$PARTITION" >/dev/null
}

copyfiles() {
  find "$SOURCE" -type d | while read dir; do
    target=$(relpath $dir)
    [ -z "$target" ] && continue
    echo "  Creating $target"
    mmd -i "$PARTITION" "::$target"
  done
  find $SOURCE -type f | while read file; do
    target=$(relpath $file)
    echo "  Copying $target"
    mcopy -i "$PARTITION" "$file" "::$target"
  done
}

insertpart() {
  dd if="$PARTITION" of="$OUTPUT" bs=$SECTOR_SIZE seek=$OFFSET_8MB >/dev/null \
    2>&1
}

# Parse options
while getopts "hfS:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    f)
      FORCE=1
      ;;
    S)
      LOGICAL_SECTOR_SIZE=$OPTARG
      ;;
    *)
      echo "Unrecognized option $opt"
      exit
  esac
done

# Parse remaining positional arguments
OUTPUT=${@:$OPTIND:1}
SIZE=${@:$OPTIND+1:1}
SOURCE=${@:$OPTIND+2:1}

if test_secsize "$LOGICAL_SECTOR_SIZE"; then
  echo "ERROR: Invalid logical sector size."
  usage
  exit 0
fi

if [ -z "$OUTPUT" ] || [ -z "$SIZE" ] || [ -z "$SOURCE" ]; then
  echo "ERROR: Missing required arguments, please see usage instructions"
  usage
  exit 0
fi

[ $FORCE ] && (rm -f $OUTPUT 2>/dev/null || true)

if [ -e "$OUTPUT" ]; then
  echo "ERROR: $OUTPUT already exists. Aborting."
  exit 1
fi

DISK_SIZE=$(disksize $SIZE)
PARTITION=${OUTPUT}.partition

echo "=============================================="
echo "Output file:      $OUTPUT"
echo "Partition size:   $SIZE MiB"
echo "Image size:       $DISK_SIZE MiB"
echo "Sector size:      $LOGICAL_SECTOR_SIZE B"
echo "Source dir:       $SOURCE"
echo "=============================================="
echo "===> Creating container image"
mkcontainer
echo "===> Creating FAT32 partition image"
mkpartition
echo "===> Copying files"
copyfiles
echo "===> Copying partition into container"
insertpart
echo "===> Removing partition image file"
rm -f "$PARTITION"
echo "===> DONE"
