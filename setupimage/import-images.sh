#!/bin/bash

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
