#!/bin/bash

# Script 1: Build the Enclave Bridge macOS app
# Uses xcodebuild to create a Release build

set -e

echo "======================================"
echo "Building Enclave Bridge"
echo "======================================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
APP_NAME="Enclave Bridge"
SCHEME_NAME="Enclave Bridge"
XCODE_PROJECT="$PROJECT_ROOT/Enclave Bridge.xcodeproj"
BUILD_DIR="$PROJECT_ROOT/build"

cd "$PROJECT_ROOT"

# Check for Xcode project
if [ ! -d "$XCODE_PROJECT" ]; then
    echo -e "${RED}Error: Xcode project not found at ${XCODE_PROJECT}${NC}"
    exit 1
fi

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build for Release
echo -e "${YELLOW}Building release build...${NC}"
xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    ONLY_ACTIVE_ARCH=NO \
    build 2>&1 | grep -E "(BUILD|error:|warning:|\*\*)" || true

APP_BUNDLE="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

if [ -d "$APP_BUNDLE" ]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo "  App: $APP_BUNDLE"
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi
