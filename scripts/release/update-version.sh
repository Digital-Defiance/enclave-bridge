#!/bin/bash

# Update version number in Xcode project
# Usage: ./scripts/release/update-version.sh <new_version>
# Example: ./scripts/release/update-version.sh 1.0.1

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ $# -eq 0 ]; then
    echo "Error: No version number provided"
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.1"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format (basic check for x.y or x.y.z)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: Invalid version format. Expected format: x.y or x.y.z (e.g., 1.0.1)"
    exit 1
fi

echo "Updating version to $NEW_VERSION..."

PBXPROJ="$PROJECT_ROOT/Enclave.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "Error: project.pbxproj not found"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(grep "MARKETING_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not detect current version"
    exit 1
fi

echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"

# Update MARKETING_VERSION in project.pbxproj
echo "Updating Xcode project..."
sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"

# Update README.md if version is mentioned
if [ -f "$PROJECT_ROOT/README.md" ]; then
    echo "Updating README.md..."
    sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" "$PROJECT_ROOT/README.md" 2>/dev/null || true
fi

# Update enclave-bridge-client package.json
CLIENT_PACKAGE="$PROJECT_ROOT/enclave-bridge-client/package.json"
if [ -f "$CLIENT_PACKAGE" ]; then
    echo "Updating enclave-bridge-client version..."
    sed -i '' "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" "$CLIENT_PACKAGE"
fi

echo ""
echo "✓ Version updated to $NEW_VERSION"
echo ""
echo "Don't forget to:"
echo "  1. Update CHANGELOG.md (if you have one)"
echo "  2. Commit the changes"
echo "  3. Tag the release: git tag v$NEW_VERSION"
