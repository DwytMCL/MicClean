#!/system/bin/sh
# MicClean installer (runs inside Magisk). Writes only inside the module folder and /data/adb/micclean.
SKIPUNZIP=0
OLD=/data/adb/modules/micclean
CFGDIR=/data/adb/micclean

ui_print "- Device: $(getprop ro.product.vendor.model) / $(getprop ro.board.platform) / Android $(getprop ro.build.version.release)"
case "$(getprop ro.board.platform)" in
  mt*) ;;
  *) ui_print "! Not a MediaTek device. MicClean is built for the Tecno KI7 (mt6768)."; abort "! Aborting, nothing changed." ;;
esac

# Pristine copies of the stock files. If MicClean is already active, the live files are our
# patched versions, so reuse the stock copies from the installed module instead.
mkdir -p "$MODPATH/orig"
for f in /vendor/etc/audio_effects.xml /vendor/etc/audio_param/SpeechVol_AudioParam.xml /vendor/etc/audio_param/VoIPVol_AudioParam.xml /vendor/etc/audio_param/AudioParamOptions.xml /vendor/etc/aurisys_config.xml /vendor/etc/aurisys_config_rv.xml; do
  n=$(basename "$f")
  if [ -f "$OLD/orig/$n" ]; then cp -f "$OLD/orig/$n" "$MODPATH/orig/$n"
  elif [ -f "$f" ] && ! grep -q micclean "$f"; then cp -f "$f" "$MODPATH/orig/$n"
  else ui_print "! $f not found, skipping it"
  fi
done

mkdir -p "$CFGDIR"
if [ -f "$CFGDIR/config" ]; then
  ui_print "- Keeping your settings in $CFGDIR/config"
  # add any settings that are new in this version
  grep -E '^[A-Z_]+=' "$MODPATH/config.default" | while IFS== read -r k rest; do
    grep -q "^$k=" "$CFGDIR/config" || grep "^$k=" "$MODPATH/config.default" >> "$CFGDIR/config"
  done
else
  cp -f "$MODPATH/config.default" "$CFGDIR/config"
  ui_print "- Default settings written to $CFGDIR/config"
fi

ui_print "- Building patched audio files"
sh "$MODPATH/build.sh" "$MODPATH" "$CFGDIR/config" > "$TMPDIR/build.log" 2>&1 || ui_print "! Some patches failed, stock files kept for those"
while read -r l; do ui_print "  $l"; done < "$TMPDIR/build.log"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/vendor/etc" 0 0 0755 0644 u:object_r:vendor_configs_file:s0
set_perm "$MODPATH/system/bin/micclean" 0 2000 0755
for f in "$MODPATH"/system/vendor/lib*/*.so; do set_perm "$f" 0 0 0644 u:object_r:vendor_file:s0; done

ui_print "- Done. Reboot, then check with:  su -c micclean status"
ui_print "- Bootloop? Hold Volume Down while booting (Magisk safe mode)"
ui_print "  or from a PC: adb wait-for-device shell magisk --remove-modules"
