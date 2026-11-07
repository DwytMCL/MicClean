#!/usr/bin/env bash
# Builds libmicclean_aurisys.so (32- and 64-bit) into module/system/vendor/lib{,64}/.
# Needs the Android NDK (r27c tested): ANDROID_NDK_HOME=/path/to/ndk ./native/build.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to your NDK folder}"
BIN=$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin)
CC="$BIN/clang"; [ -x "$CC" ] || CC="$BIN/clang.exe"

# RNNoise 0.2 (BSD-3-Clause, Xiph.Org), includes the trained model
if [ ! -d rnnoise-0.2 ]; then
  curl -sSL https://github.com/xiph/rnnoise/releases/download/v0.2/rnnoise-0.2.tar.gz | tar -xz
fi
R=rnnoise-0.2/src
SRCS="micclean_aurisys.c $R/denoise.c $R/rnn.c $R/rnnoise_data.c $R/rnnoise_tables.c $R/nnet.c \
      $R/nnet_default.c $R/parse_lpcnet_weights.c $R/celt_lpc.c $R/kiss_fft.c $R/pitch.c"

for t in armv7a-linux-androideabi29:lib:-mfpu=neon aarch64-linux-android29:lib64:; do
  IFS=: read -r target dir extra <<< "$t"
  out=../module/system/vendor/$dir
  mkdir -p "$out"
  "$CC" --target="$target" $extra -O2 -fPIC -shared -fvisibility=hidden -w \
    -Irnnoise-0.2/include -I$R -Icompat $SRCS \
    -o "$out/libmicclean_aurisys.so" -lm -ldl -llog -Wl,--gc-sections -Wl,-z,max-page-size=16384 -s
  echo "built $out/libmicclean_aurisys.so"
done
