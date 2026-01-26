#!/bin/bash
# Clean all build artifacts
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🧹 Cleaning all build artifacts..."

# Clean Swift build
echo "   Cleaning Swift build..."
rm -rf "$PROJECT_ROOT/build"
rm -rf ~/Library/Developer/Xcode/DerivedData/Enclave-*

# Clean Node.js client build
echo "   Cleaning enclave-bridge-client..."
rm -rf "$PROJECT_ROOT/enclave-bridge-client/dist"

echo ""
echo "✅ Clean complete!"
