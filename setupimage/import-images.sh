#!/bin/bash
# Cloudy: An open LAMP benchmark suite
# Copyright (C) 2010 Adam Litke, IBM Corporation
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

################################################################
# import-images.sh - import random image data into a populated #
# MediaWiki instance.                                          #
################################################################
. /media/config

DIR=/tmp/image-import

IMAGES=`echo "select il_to from imagelinks" | mysql --user=root --password=linux99  wikidb | tail -n +2`

mkdir -p $DIR
printf "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A" > $DIR/header
for i in $IMAGES; do
  echo "image: $i"
  dd if=/dev/urandom of="$DIR/data" bs=1 count=$IMAGE_SIZE
  cat $DIR/header $DIR/data > "$DIR/$i"
done

pushd /var/www/wiki
php /usr/share/mediawiki/maintenance/importImages.php --overwrite /tmp/image-import png jpg gif bmp PNG JPG GIF BMP
popd

rm -rf $DIR
exit 0
