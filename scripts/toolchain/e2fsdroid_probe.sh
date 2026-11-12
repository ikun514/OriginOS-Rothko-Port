#!/system/bin/sh
# e2fsdroid_probe.sh -- 找 e2fsdroid 的正确调用方式（写入 SELinux xattr）
set -u
. /data/local/tmp/toolchain/dev_lib.sh
W=/data/local/tmp/lab/e2p
rm -rf $W; mkdir -p $W/src/bin
echo hello > $W/src/hello.txt
mkdir -p $W/src/bin; printf '#!/system/bin/sh\n' > $W/src/bin/a.sh
FC=/system/etc/selinux/plat_file_contexts
FSC=/system/etc/selinux/plat_fs_config
ls -l $FC $FSC 2>&1

run() {
  desc=$1; shift
  rm -f $W/t.img
  mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -d $W/src -O ^has_journal $W/t.img 16384 2>/dev/null
  echo "=== $desc ==="
  echo "  cmd: e2fsdroid $*"
  out=$(/system/bin/e2fsdroid "$@" $W/t.img 2>&1)
  rc=$?
  echo "  rc=$rc"
  echo "$out" | head -6 | sed 's/^/  /'
  # 检查标签是否写入：用 debugfs? 没有; 用 dumpe2fs?
  /system/bin/tune2fs -l $W/t.img >/dev/null 2>&1 && echo "  image ok"
}

run "A: -f src -a mp -S fc -C fscode" -f $W/src -a /system -S $FC -C $FSC
run "B: -e -S fc -C fscode -a mp" -e -S $FC -C $FSC -a /system
run "C: -f src -a mp -S fc" -f $W/src -a /system -S $FC
run "D: -d basefs -f src -a mp -S fc" -d $W/t.img -f $W/src -a /system -S $FC
run "E: -T ts -f src -a mp -S fc -C fscode" -T 1700000000 -f $W/src -a /system -S $FC -C $FSC
run "F: no options at all"
echo "=== e2fsdroid 源码级帮助 ==="
strings /system/bin/e2fsdroid 2>/dev/null | grep -iE "^-|usage|extended|inode|base|source|skip|overwrite|delay" | head -40
echo "=== done ==="
