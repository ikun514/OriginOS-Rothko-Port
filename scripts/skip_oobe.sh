#!/system/bin/sh
echo "=== OOBE skip step ==="
settings put global setup_skipped 1
settings put secure setup_wizard_has_run 1
settings put secure setup_wizard_display 0
setprop persist.sys.wizard.setup 3 2>/dev/null
cmd package set-home-activity com.bbk.launcher2/.Launcher 2>&1
pm disable-user --user 0 com.vivo.setupwizard 2>&1
am force-stop com.vivo.setupwizard 2>&1
sleep 1
am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>&1 | head -3
sleep 3
echo "=== verify ==="
settings get global setup_skipped
settings get secure setup_wizard_has_run
pm list packages -d 2>/dev/null | grep -i setup
cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -2
dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -3
echo DONE
