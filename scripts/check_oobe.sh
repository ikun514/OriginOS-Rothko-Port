#!/system/bin/sh
echo "=== setupwizard props ==="
getprop | grep -iE 'setup|provision|oobe' | head -20
echo "=== settings global setup-ish ==="
settings list global 2>/dev/null | grep -iE 'setup|provision|device_provisioned' | head -10
echo "=== settings secure setup-ish ==="
settings list secure 2>/dev/null | grep -iE 'setup|user_setup' | head -10
echo "=== setupwizard packages ==="
pm list packages 2>/dev/null | grep -iE 'setupwizard|provision' | head -10
echo "=== current home ==="
cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -2
echo DONE
