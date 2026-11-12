#!/system/bin/sh
# KernelSU module service.sh (late boot): one-time cross-brand data cleanup for apps whose
# databases came from HyperOS and crash vivo providers (e.g. contacts).
LOG=/data/local/tmp/portfix.log
{
  echo "==== $(date) service ===="
  if [ ! -f /data/local/tmp/portfix/.contacts_cleared_v1 ]; then
    echo "clearing contacts/calllog providers (HyperOS db incompatible)"
    pm clear com.android.providers.contacts 2>&1
    pm clear com.android.providers.telephony 2>&1
    touch /data/local/tmp/portfix/.contacts_cleared_v1
  fi
} >> "$LOG" 2>&1
