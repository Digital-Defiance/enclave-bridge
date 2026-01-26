#!/bin/bash

# Master script: Build, sign, notarize, and create DMG in one go
# Usage: ./scripts/release/build-all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Complete Enclave Bridge Build Pipeline"
echo "======================================"
echo ""

# Check prerequisites
if [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ]; then
    echo "⚠️  Notarization credentials not set."
    echo "   The app will be built and signed, but not notarized."
    echo ""
    echo "To enable notarization, set:"
    echo "  export APPLE_ID=\"your@email.com\""
    echo "  export APPLE_TEAM_ID=\"XXXXXXXXXX\""
    echo ""
    read -p "Continue without notarization? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_NOTARIZE=true
fi

# Step 1: Build
"$SCRIPT_DIR/1-build-app.sh"

# Step 2: Sign
"$SCRIPT_DIR/2-sign-app.sh"

# Step 3: Notarize (if credentials available)
if [ "$SKIP_NOTARIZE" != "true" ]; then
    "$SCRIPT_DIR/3-notarize-app.sh"
else
    echo ""
    echo "⚠️  Skipping notarization"
fi

# Step 4: Create DMG
"$SCRIPT_DIR/4-create-dmg.sh"

echo ""
echo "======================================"
echo "✓ Build Complete!"
echo "======================================"
echo ""
echo "Distribution file: build/EnclaveBridge.dmg"
echo ""

if [ "$SKIP_NOTARIZE" == "true" ]; then
    echo "⚠️  Note: App is signed but NOT notarized."
    echo "   Users may see Gatekeeper warnings."
    echo "   Set up notarization credentials and rebuild for distribution."
fi
