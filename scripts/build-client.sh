#!/bin/bash
# Build the enclave-bridge-client TypeScript library
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/enclave-bridge-client"

echo "🔨 Building enclave-bridge-client TypeScript library..."
echo "   Directory: $CLIENT_DIR"

cd "$CLIENT_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Clean previous build
echo "🧹 Cleaning previous build..."
npm run clean 2>/dev/null || true

# Build
echo "🔧 Compiling TypeScript..."
npm run build

if [ -d "dist" ]; then
    echo ""
    echo "✅ Build successful!"
    echo "   Output: $CLIENT_DIR/dist/"
    ls -la dist/
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi
