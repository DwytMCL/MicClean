#!/system/bin/sh
# MicClean: rewrites the voice_communication (VoIP) pre-processing chain in audio_effects.xml.
# Usage: patch_effects.sh <pristine xml> <output xml> <config>
# Keeps the vendor's own aec/ns/agc effects (MediaTek libaudiopreprocessing_mtk.so) and can add
# the AOSP AGC2 limiter from libaudiopreprocessing.so. Added lines end with <!--micclean-->.

SRC="$1"; OUT="$2"; CFG="$3"
[ -f "$SRC" ] || { echo "no source $SRC"; exit 1; }
VOIP_AEC=1; VOIP_NS=1; VOIP_AGC=0; VOIP_LIMITER=1; VOIP_RNNOISE=0
[ -f "$CFG" ] && . "$CFG"

# AOSP AGC2 exists only if the AOSP library is there and knows it
LIM_OK=0
for l in /vendor/lib64/soundfx /vendor/lib/soundfx; do
  grep -q "Gain Control 2" "$l/libaudiopreprocessing.so" 2>/dev/null && LIM_OK=1
done
[ "$LIM_OK" = 1 ] || VOIP_LIMITER=0

awk -v aec="$VOIP_AEC" -v ns="$VOIP_NS" -v agc="$VOIP_AGC" -v lim="$VOIP_LIMITER" -v rnn=0 '
BEGIN {
  M = "<!--micclean-->"
  au["aec"] = "bb392ec0-8d4d-11e0-a896-0002a5d5c51b"
  au["ns"]  = "c06c8400-8e06-11e0-9cb6-0002a5d5c51b"
  au["agc"] = "aa8130e0-66fc-11e0-bad0-0002a5d5c51b"
}
function attr(line, a,   r) {
  if (match(line, a "=\"[^\"]*\"")) { r = substr(line, RSTART, RLENGTH); sub(/^[^"]*"/, "", r); sub(/"$/, "", r); return r }
  return ""
}
NR == FNR {                                   # pass 1: what is already defined (ignoring XML comments)
  if (incom) { if (index($0, "-->")) incom = 0; next }
  if ($0 ~ /^[ \t]*<!--/) { if (!index($0, "-->")) incom = 1; next }
  if ($0 ~ /<library/ && $0 ~ /path="libaudiopreprocessing\.so"/) aosplib = attr($0, "name")
  if ($0 ~ /<effect /) def[attr($0, "name")] = 1
  if ($0 ~ /<preprocess>/) haspre = 1
  if ($0 ~ /<stream / && $0 ~ /voice_communication/) hasvc = 1
  next
}
FNR == 1 {
  needlib = (aosplib == "")
  if (needlib) aosplib = "micclean_aosp_pre"
  chain = ""
  # RNNoise registers as the AEC type (the only pre-processor this HAL runs), so it takes the aec slot
  if (rnn == 1) chain = chain "                <apply effect=\"micclean_rnnoise\"/>" M "\n"
  else if (aec == 1) chain = chain "                <apply effect=\"aec\"/>" M "\n"
  if (ns  == 1) chain = chain "                <apply effect=\"ns\"/>" M "\n"
  if (agc == 1) chain = chain "                <apply effect=\"agc\"/>" M "\n"
  if (lim == 1) chain = chain "                <apply effect=\"micclean_agc2\"/>" M "\n"
}
/<\/libraries>/ && needlib && lim == 1 { print "        <library name=\"" aosplib "\" path=\"libaudiopreprocessing.so\"/>" M }
/<\/libraries>/ && rnn == 1 { print "        <library name=\"micclean_rnnoise\" path=\"libmicclean_rnnoise.so\"/>" M }
/<\/effects>/ {
  for (k in au) if ((k == "aec" && aec == 1 || k == "ns" && ns == 1 || k == "agc" && agc == 1) && !def[k])
    print "        <effect name=\"" k "\" library=\"" aosplib "\" uuid=\"" au[k] "\"/>" M
  if (rnn == 1) print "        <effect name=\"micclean_rnnoise\" library=\"micclean_rnnoise\" uuid=\"8a1f6b22-3c4d-4e5f-a6b7-6d63726e6e31\"/>" M
  if (lim == 1) print "        <effect name=\"micclean_agc2\" library=\"" aosplib "\" uuid=\"89f38e65-d4d2-4d64-ad0e-2b3e799ea886\"/>" M
}
/<\/audio_effects_conf>/ && !haspre {
  print "    <preprocess>" M; print "        <stream type=\"voice_communication\">" M
  printf "%s", chain; print "        </stream>" M; print "    </preprocess>" M
}
rnn == 1 && /<effect / && attr($0, "name") == "aec" { next }   # one AEC-type effect only: ours
invc && /<apply / { next }                    # drop the vendor chain, ours replaces it
invc && /<\/stream>/ { invc = 0 }
{ print }
/<preprocess>/ && !hasvc { print "        <stream type=\"voice_communication\">" M; printf "%s", chain; print "        </stream>" M }
/<stream / && /voice_communication/ { invc = 1; printf "%s", chain }
' "$SRC" "$SRC" > "$OUT"

if ! grep -q "</audio_effects_conf>" "$OUT"; then
  cp -f "$SRC" "$OUT"; echo "effects patch failed, kept original"; exit 2
fi
echo "VoIP effects: AEC=$VOIP_AEC NS=$VOIP_NS AGC=$VOIP_AGC LIMITER=$VOIP_LIMITER"
