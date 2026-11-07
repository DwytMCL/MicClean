#!/system/bin/sh
# MicClean: regenerate the overlay files from the pristine copies in <moddir>/orig using the config.
# Usage: build.sh <moddir> <config>
MD="$1"; CFG="$2"
CALL_MIC_OFFSET=0; CALL_SPK_OFFSET=0; VOIP_MIC_OFFSET=0
. "$CFG"
VE="$MD/system/vendor/etc"
mkdir -p "$VE/audio_param"
T="$MD/.tmp"; RC=0

put() { # write without replacing the inode, so an already-mounted file updates in place
  if [ -f "$2" ]; then cat "$1" > "$2"; else cp -f "$1" "$2"; fi
  rm -f "$1"
}

if [ -f "$MD/orig/audio_effects.xml" ]; then
  sh "$MD/patch_effects.sh" "$MD/orig/audio_effects.xml" "$T" "$CFG" || RC=1
  put "$T" "$VE/audio_effects.xml"
fi
if [ -f "$MD/orig/SpeechVol_AudioParam.xml" ]; then
  sh "$MD/patch_gain.sh" "$MD/orig/SpeechVol_AudioParam.xml" "$T" "$CALL_MIC_OFFSET" "$CALL_SPK_OFFSET" || RC=1
  put "$T" "$VE/audio_param/SpeechVol_AudioParam.xml"
fi
if [ -f "$MD/orig/VoIPVol_AudioParam.xml" ]; then
  sh "$MD/patch_gain.sh" "$MD/orig/VoIPVol_AudioParam.xml" "$T" "$VOIP_MIC_OFFSET" 0 || RC=1
  put "$T" "$VE/audio_param/VoIPVol_AudioParam.xml"
fi

if [ -f "$MD/orig/AudioParamOptions.xml" ]; then
  # Experimental: MediaTek dual-mic noise reduction for SIM calls (Tecno ships it disabled)
  if [ "${CALL_DUALMIC:-0}" = 1 ]; then v=yes; else v=no; fi
  sed "s|<Param name=\"MTK_DUAL_MIC_SUPPORT\" value=\"[^\"]*\"|<Param name=\"MTK_DUAL_MIC_SUPPORT\" value=\"$v\"|" \
    "$MD/orig/AudioParamOptions.xml" > "$T"
  put "$T" "$VE/audio_param/AudioParamOptions.xml"
  echo "Dual-mic noise reduction for calls: $v"
fi

# RNNoise as a MediaTek Aurisys plugin on the VoIP uplink (the HAL ignores Android effects for VoIP)
for n in aurisys_config.xml aurisys_config_rv.xml; do
  [ -f "$MD/orig/$n" ] || continue
  if [ "${VOIP_RNNOISE:-0}" = 1 ]; then
    sh "$MD/patch_aurisys.sh" "$MD/orig/$n" "$T" || RC=1
  else
    cp -f "$MD/orig/$n" "$T"
  fi
  put "$T" "$VE/$n"
done
[ "${VOIP_RNNOISE:-0}" = 1 ] && echo "AI noise suppression (RNNoise): on, strength ${VOIP_RNNOISE_STRENGTH:-2}" || echo "AI noise suppression (RNNoise): off"

# RNNoise strength, read by the effect each time a call starts (0 = AI only, 1-3 = voice gate)
echo "strength=${VOIP_RNNOISE_STRENGTH:-2}" > "$T"
put "$T" "$VE/micclean_rnnoise.conf"

chmod 0644 "$VE"/aurisys_config*.xml "$VE/micclean_rnnoise.conf" "$VE/audio_effects.xml" "$VE"/audio_param/*.xml 2>/dev/null
chcon u:object_r:vendor_configs_file:s0 "$VE"/aurisys_config*.xml "$VE/micclean_rnnoise.conf" "$VE/audio_effects.xml" "$VE"/audio_param/*.xml 2>/dev/null
exit $RC
