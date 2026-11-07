#!/system/bin/sh
# MicClean: shifts every mic (ul_gain) value in a MediaTek *Vol_AudioParam.xml by an offset in dB.
# Usage: patch_gain.sh <pristine xml> <output xml> <offset dB> <extra offset for speakerphone dB>
SRC="$1"; OUT="$2"; OFF="${3:-0}"; SPK="${4:-0}"
[ -f "$SRC" ] || { echo "no source $SRC"; exit 1; }

awk -v off="$OFF" -v spk="$SPK" '
function attr(line, a,   r) {
  if (match(line, a "=\"[^\"]*\"")) { r = substr(line, RSTART, RLENGTH); sub(/^[^"]*"/, "", r); sub(/"$/, "", r); return r }
  return ""
}
NR == FNR {                                   # pass 1: which param_ids are speakerphone profiles
  if ($0 ~ /<Param path=/) { p = attr($0, "path"); if (p ~ /(^|,)SPK(,|$)/) isspk[attr($0, "param_id")] = 1 }
  next
}
/<ParamUnit / { cur = attr($0, "param_id") }
/<Param name="ul_gain"/ {
  v = attr($0, "value") + 0
  if (v > 0) {                                # 0 means "unused profile", leave it alone
    n = v + off + ((cur in isspk) ? spk : 0)
    if (n < 0) n = 0; if (n > 45) n = 45
    sub(/value="[^"]*"/, "value=\"" n "\"")
  }
}
/<\/AudioParam>/ { print "<!--micclean offset=" off " spk=" spk "-->" }
{ print }
' "$SRC" "$SRC" > "$OUT"

grep -q "</AudioParam>" "$OUT" || { cp -f "$SRC" "$OUT"; echo "gain patch failed, kept original"; exit 2; }
echo "$(basename "$SRC"): mic gain ${OFF} dB (speakerphone extra ${SPK} dB)"
