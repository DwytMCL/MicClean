# MicClean for Tecno Spark 10 Pro (KI7, mt6768), crDroid 10.5 + Magisk

Makes you sound less loud and less noisy to the other person on calls. Systemless: nothing on
/vendor or /system is modified; Magisk overlays three patched copies, and removing the module
restores stock instantly.

## What it changes

| Call type | Stock on this phone | MicClean default |
|---|---|---|
| Regular phone calls (SIM, VoLTE) | Mic gain 21-23 dB handset, 26-27 dB speaker, 28 dB headset | 6 dB lower everywhere (`CALL_MIC_OFFSET=-6`) |
| Internet calls (WhatsApp, Messenger, Telegram, Meet) | Mic gain 25-34 dB, chain = echo cancel + noise suppression + auto gain | 6 dB lower, chain = echo cancel + noise suppression + limiter, auto gain off |

Regular calls are processed by MediaTek's modem speech DSP, which already runs its own noise
reduction. Android's NS/AEC effects only apply to internet calls, so for SIM calls the lever is
the mic gain (too much gain is what makes both your voice and room noise loud).

Patched files: `/vendor/etc/audio_effects.xml`, `/vendor/etc/audio_param/SpeechVol_AudioParam.xml`,
`/vendor/etc/audio_param/VoIPVol_AudioParam.xml`.

## AI noise suppression (v1.3)

- Internet calls (Discord, WhatsApp, Messenger, Telegram, Meet): RNNoise 0.2 plus a voice gate runs
  as a MediaTek Aurisys plugin (`libmicclean_aurisys.so`) right after MediaTek's own VoIP speech
  enhancement. This HAL ignores normal Android audio effects for VoIP, which is why the plugin route
  is needed. Toggle: `micclean set VOIP_RNNOISE 0/1`; strength 0-3: `micclean set VOIP_RNNOISE_STRENGTH 2`
  (also in the MicClean app). Strength changes apply on the next call.
- SIM calls: the mic goes straight to the modem's speech processor, so no Android-side filter can
  touch it. Option there: MediaTek dual-mic noise reduction, `micclean set CALL_DUALMIC 1` to try it.

## Install

1. Copy `MicClean-v1.3.zip` to the phone.
2. Magisk app > Modules > Install from storage > pick the zip.
3. Reboot.
4. Check: `adb shell su -c micclean status` (or in Termux: `su -c micclean status`).

## Tuning the mic gain (no reboot needed)

```
su -c micclean set CALL_MIC_OFFSET -8     # SIM calls: quieter
su -c micclean set CALL_MIC_OFFSET -3     # SIM calls: a bit louder than default
su -c micclean set CALL_SPK_OFFSET -4     # speakerphone only, extra
su -c micclean set VOIP_MIC_OFFSET -6     # internet calls
su -c micclean set VOIP_AGC 1             # turn stock auto gain back on
su -c micclean set VOIP_LIMITER 0         # turn the limiter off
su -c micclean reset                      # back to defaults
```

Each `set` restarts the audio service for a second, so do it between calls. Test by calling a
friend or your voicemail. Go in 2-3 dB steps; 0 is stock.

## Remove / recover

- Normal removal: Magisk > Modules > MicClean > Remove > reboot.
- Phone stuck booting (bootloop):
  - Magisk safe mode: power on, and once the boot logo appears keep pressing Volume Down
    until the lock screen. All modules are disabled; remove MicClean in Magisk and reboot.
  - Or from the PC while it is stuck on the logo:
    `adb wait-for-device shell magisk --remove-modules` (removes all modules and reboots).
  - Or: `adb shell su -c "touch /data/adb/modules/micclean/remove"` then reboot.
- No sound or no mic at all after install: `su -c micclean reset`, and if that does not fix it,
  remove the module. Settings live in `/data/adb/micclean/config` and are deleted on removal.
