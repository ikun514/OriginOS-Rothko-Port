#!/system/bin/sh
echo "=== push progress ==="
ls -l /sdcard/work/images/
echo "=== rothko vendor erofs info ==="
dump.erofs -s /dev/block/dm-11 2>&1 | grep -Ei 'compr|feature|lz4|zstd|lzma|deflate|inodes|blocks'
echo "=== rothko system erofs info ==="
dump.erofs -s /dev/block/dm-9 2>&1 | grep -Ei 'compr|feature|lz4|zstd|lzma|deflate|inodes|blocks'
echo "=== vivo product compression (already extracted) ==="
dump.erofs -s /data/local/tmp/work/images/product.img 2>&1 | grep -Ei 'compr|feature|lz4|zstd|lzma|deflate'
echo "=== dump.erofs help (algorithms view) ==="
dump.erofs --help 2>&1 | head -30
