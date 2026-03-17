#!/usr/bin/env bash
# Generate a self-signed code signing certificate for SnapForge CI builds.
# This preserves macOS TCC permissions across Sparkle auto-updates.
#
# Usage: ./scripts/generate-signing-cert.sh [cert-name] [validity-days]
#
# This script:
#   1. Generates a self-signed "Code Signing" certificate via OpenSSL
#   2. Exports it as a .p12 file
#   3. Imports into login keychain for local builds
#   4. Prints base64-encoded output ready for GitHub Secrets
#
# After running, add these GitHub Secrets:
#   SELF_SIGNED_CERT_P12       — the base64 output
#   SELF_SIGNED_CERT_PASSWORD  — the password you enter during export

set -euo pipefail

CERT_NAME="${1:-SnapForge Self-Signed}"
VALIDITY_DAYS="${2:-3650}"  # 10 years default

TEMP_DIR=$(mktemp -d)
P12_PATH="$TEMP_DIR/signing-cert.p12"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=== SnapForge Self-Signed Certificate Generator ==="
echo ""
echo "Certificate name: $CERT_NAME"
echo "Validity: $VALIDITY_DAYS days"
echo ""

# 1. Create OpenSSL config with Code Signing EKU
echo "-> Generating self-signed code signing certificate..."
cat > "$TEMP_DIR/cert.cfg" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
x509_extensions    = codesign

[ req_dn ]
CN = $CERT_NAME
O  = SnapForge

[ codesign ]
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 2. Generate key + self-signed certificate
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TEMP_DIR/key.pem" \
  -out "$TEMP_DIR/cert.pem" \
  -days "$VALIDITY_DAYS" \
  -config "$TEMP_DIR/cert.cfg" \
  2>/dev/null

# 3. Prompt for .p12 password
echo ""
echo "-> Enter a password for the .p12 export (needed for SELF_SIGNED_CERT_PASSWORD):"
read -rs P12_PASSWORD
echo ""

if [ -z "$P12_PASSWORD" ]; then
  echo "Error: password cannot be empty"
  exit 1
fi

# 4. Export as P12
openssl pkcs12 -export \
  -out "$P12_PATH" \
  -inkey "$TEMP_DIR/key.pem" \
  -in "$TEMP_DIR/cert.pem" \
  -passout "pass:$P12_PASSWORD" \
  2>/dev/null

# 5. Import into login keychain for local builds
echo "-> Importing certificate into login keychain..."
security import "$P12_PATH" -P "$P12_PASSWORD" \
  -A -t cert -f pkcs12 -T /usr/bin/codesign \
  -k "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
  || security import "$P12_PATH" -P "$P12_PASSWORD" \
    -A -t cert -f pkcs12 -T /usr/bin/codesign \
    -k "$HOME/Library/Keychains/login.keychain" 2>/dev/null \
  || {
    echo "Warning: Could not auto-import into login keychain. Import manually:"
    echo "  security import /path/to/signing-cert.p12 -P <password> -k ~/Library/Keychains/login.keychain-db"
  }

# 6. Trust the certificate for code signing
echo "-> Trusting certificate for code signing..."
security add-trusted-cert -d -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$TEMP_DIR/cert.pem" 2>/dev/null \
  || security add-trusted-cert -d -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain" "$TEMP_DIR/cert.pem" 2>/dev/null \
  || echo "Warning: Could not auto-trust. Trust manually in Keychain Access."

# 7. Verify identity is available
echo ""
echo "-> Verifying certificate in login keychain..."
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "Certificate '$CERT_NAME' is available for code signing"
else
  echo "Warning: Certificate imported but not recognized as code signing identity."
  echo "  You may need to trust it manually in Keychain Access:"
  echo "  1. Open Keychain Access"
  echo "  2. Find '$CERT_NAME'"
  echo "  3. Double-click -> Trust -> Code Signing -> Always Trust"
  echo ""
  echo "  Available signing identities:"
  security find-identity -v -p codesigning
fi

# 8. Base64 encode for GitHub Secrets
B64_CERT=$(base64 < "$P12_PATH")

echo ""
echo "============================================"
echo "Certificate generated successfully!"
echo "============================================"
echo ""
echo "Add these GitHub Secrets to your repository:"
echo ""
echo "1. SELF_SIGNED_CERT_P12"
echo "   Value (base64-encoded, copy everything between the markers):"
echo ""
echo "--- BEGIN BASE64 ---"
echo "$B64_CERT"
echo "--- END BASE64 ---"
echo ""
echo "2. SELF_SIGNED_CERT_PASSWORD"
echo "   Value: (the password you entered above)"
echo ""
echo "============================================"
echo "Certificate name for codesign: \"$CERT_NAME\""
echo "Valid for: $VALIDITY_DAYS days"
echo "============================================"
