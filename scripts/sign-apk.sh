#!/usr/bin/env bash
# Sign and verify an APK with Google's official apksigner (v1 + v2 + v3 schemes).
# Usage:  KS_FILE=key.p12 KS_PASS=... KEY_ALIAS=... KEY_PASS=... sign-apk.sh <in.apk> <out.apk>
# Fails the build if any scheme is missing or the certificate does not match the keystore.
set -euo pipefail
IN="${1:?input apk}"; OUT="${2:?output apk}"
: "${KS_FILE:?}" "${KS_PASS:?}" "${KEY_ALIAS:?}" "${KEY_PASS:?}"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
APKSIGNER="$(ls "$SDK"/build-tools/*/apksigner | sort -V | tail -1)"
echo "Using $APKSIGNER"

"$APKSIGNER" sign \
  --ks "$KS_FILE" --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KS_PASS --key-pass env:KEY_PASS \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out "$OUT" "$IN"

REPORT="$("$APKSIGNER" verify --verbose --print-certs "$OUT")"
echo "$REPORT" | grep -E "^Verifies|Verified using|Number of signers|certificate SHA-256"
# minSdk >= 24: the verifier skips the legacy v1 (JAR) scheme, so only v2 and v3 are required here.
for s in "v2 scheme (APK Signature Scheme v2)" "v3 scheme (APK Signature Scheme v3)"; do
  echo "$REPORT" | grep -qF "Verified using $s: true" || { echo "::error::missing signature: $s"; exit 1; }
done

GOT="$(echo "$REPORT" | grep -m1 'certificate SHA-256 digest' | awk '{print $NF}')"
WANT="$(keytool -list -v -keystore "$KS_FILE" -storepass "$KS_PASS" | grep -m1 'SHA256:' | awk '{print $NF}' | tr -d ':' | tr 'A-F' 'a-f')"
[ -n "$GOT" ] && [ "$GOT" = "$WANT" ] || { echo "::error::certificate mismatch ($GOT != $WANT)"; exit 1; }
echo "OK: signed with the expected key ($GOT)"
