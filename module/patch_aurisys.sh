#!/system/bin/sh
# MicClean: route MediaTek Aurisys VoIP uplink through libmicclean_aurisys.so (wraps lib_speech_enh.so
# and adds RNNoise). Usage: patch_aurisys.sh <pristine aurisys_config.xml> <output>
SRC="$1"; OUT="$2"
[ -f "$SRC" ] || { echo "no source $SRC"; exit 1; }

awk '
NR == FNR {                                   # pass 1: copy the mtk_speech_enh library block
  if ($0 ~ /<library name="mtk_speech_enh"[ \t]*$/) grab = 1
  if (grab) blk = blk $0 "\n"
  if (grab && $0 ~ /<\/library>/) grab = 0
  next
}
/aurisys_scenario="AURISYS_SCENARIO_VOIP(_WITHOUT_AEC)?"/ && /<aurisys_scenario / { invoip = 1 }
invoip { gsub(/"mtk_speech_enh"/, "\"micclean_enh\"") }
invoip && /<\/aurisys_scenario>/ { invoip = 0 }
/<\/hal_librarys>/ && blk != "" {
  b = blk
  sub(/name="mtk_speech_enh"/, "name=\"micclean_enh\"", b)
  gsub(/lib_speech_enh\.so/, "libmicclean_aurisys.so", b)
  sub(/adb_cmd_key="[^"]*"/, "adb_cmd_key=\"MICCLEAN\"", b)
  printf "        <!-- micclean: lib_speech_enh + RNNoise -->\n%s", b
}
{ print }
' "$SRC" "$SRC" > "$OUT"

if ! grep -q "</aurisys_config>" "$OUT" || ! grep -q 'library name="micclean_enh"' "$OUT"; then
  cp -f "$SRC" "$OUT"; echo "aurisys patch failed, kept original"; exit 2
fi
echo "Aurisys VoIP uplink: RNNoise plugin on"
