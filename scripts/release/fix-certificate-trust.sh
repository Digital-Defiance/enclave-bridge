#!/bin/bash

# Fix certificate trust issues in Keychain
# Run this if codesign complains about certificates not being trusted

set -e

echo "======================================"
echo "Certificate Trust Troubleshooting"
echo "======================================"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}Step 1: List all code signing certificates${NC}"
security find-identity -v -p codesigning

echo ""
echo -e "${YELLOW}Step 2: Check for trust issues${NC}"
echo ""

# Check Developer ID certificates
echo "Developer ID Application certificates:"
DEV_ID_CERTS=$(security find-identity -v -p codesigning | grep "Developer ID Application" || echo "None found")
echo "$DEV_ID_CERTS"

echo ""
echo "3rd Party Mac Developer certificates:"
THIRD_PARTY_CERTS=$(security find-identity -v | grep "3rd Party Mac Developer" || echo "None found")
echo "$THIRD_PARTY_CERTS"

echo ""
echo -e "${YELLOW}Step 3: Verify certificate chain${NC}"
echo ""

# Find first valid Developer ID cert
CERT_HASH=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')

if [ -n "$CERT_HASH" ]; then
    echo "Checking certificate: $CERT_HASH"
    security verify-cert -c "$CERT_HASH" 2>&1 || true
else
    echo "No Developer ID certificate found"
fi

echo ""
echo -e "${YELLOW}Common Solutions:${NC}"
echo ""
echo "1. If certificate shows CSSMERR_TP_NOT_TRUSTED:"
echo "   - Open Keychain Access"
echo "   - Find 'Apple Worldwide Developer Relations Certification Authority'"
echo "   - Double-click → Trust → Always Trust"
echo "   - Find 'Developer ID Certification Authority'"
echo "   - Double-click → Trust → Always Trust"
echo ""
echo "2. If certificate shows '0 valid identities found':"
echo "   - Download certificate from https://developer.apple.com/account/resources/certificates/list"
echo "   - Double-click to install"
echo "   - Make sure you have the private key (created with CSR)"
echo ""
echo "3. If private key is missing:"
echo "   - You need to create a new certificate"
echo "   - The private key was on the Mac that created the CSR"
echo ""
echo "4. To manually set trust for Apple root certificates:"
echo "   curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"
echo "   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain AppleWWDRCAG3.cer"
