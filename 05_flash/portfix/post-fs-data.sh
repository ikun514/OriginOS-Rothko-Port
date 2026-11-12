#!/system/bin/sh
# KernelSU module post-fs-data: SELinux permissive + one-time cross-brand data cleanse
LOG=/data/local/tmp/portfix.log
{
  echo "==== $(date) post-fs-data ===="
  echo "before: $(getenforce)"
  setenforce 0 2>&1
  echo "after: $(getenforce)"

  # fixup: patched system libs baked into system image (v05+). If /data copies exist and
  # image is older (v02), still overlay them for compatibility.
  bind_overlay() {
    SRC="$1"; DST="$2"
    if [ -f "$SRC" ] && [ -f "$DST" ]; then
      chcon u:object_r:system_lib_file:s0 "$SRC" 2>/dev/null
      if mount --bind "$SRC" "$DST"; then
        echo "bind OK: $DST ($(sha256sum $DST | cut -c1-16))"
      else
        echo "bind FAILED: $DST"
      fi
    else
      echo "bind skip: src=$SRC dst=$DST"
    fi
  }
  bind_overlay /data/local/tmp/portfix/libvivo_servers.so /system/lib64/libvivo_servers.so
  bind_overlay /data/local/tmp/portfix/libsensorservice_patched.so /system/lib64/libsensorservice.so

  # one-time: remove stale HyperOS permission/appops state (caused AppOpsManager crash)
  if [ ! -f /data/local/tmp/portfix/.cleansed_v1 ]; then
    echo "== cleansing stale cross-brand state =="
    rm -f /data/misc/apexdata/com.android.permission/access.abx*
    rm -f /data/misc_de/0/apexdata/com.android.permission/access.abx*
    rm -f /data/system/appops_accesses.xml*
    rm -rf /data/system/appops/discrete/* /data/system/appops/history/* 2>/dev/null
    touch /data/local/tmp/portfix/.cleansed_v1
    echo "cleansed"
  fi
} >> "$LOG" 2>&1
