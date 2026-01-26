#!/bin/bash

# Update macOS app version (Xcode project only)
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

# Find the Xcode project (handle spaces in path)
XCODEPROJ=$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcodeproj" -type d | head -1)

if [ -z "$XCODEPROJ" ]; then
    echo "Error: Xcode project not found"
    exit 1
fi

PBXPROJ="$XCODEPROJ/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "Error: project.pbxproj not found at $PBXPROJ"
    exit 1
fi

echo "Found project: $XCODEPROJ"

# Get current version from Xcode project
CURRENT_VERSION=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
[ -n "$CURRENT_VERSION" ] && echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"

# Update MARKETING_VERSION in project.pbxproj
echo "Updating Xcode project..."
# Use perl for reliable in-place edit even when version is short like 1.0
perl -pi -e "s/MARKETING_VERSION = [0-9]+\.[0-9]+(?:\.[0-9]+)?;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"

# Update Info.plist version (if it exists)
INFO_PLIST="$PROJECT_ROOT/EnclaveBridge/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    echo "Updating Info.plist..."
    # Note: Full version update in plist would require additional tools
    # This is a placeholder - you may need to use plutil or PlistBuddy
fi

# Update README.md if version is mentioned
if [ -f "$PROJECT_ROOT/README.md" ]; then
    echo "Updating README.md..."
    # Only update explicit version tags, not the general description
    perl -pi -e "s/v[0-9]+\.[0-9]+(?:\.[0-9]+)?/v$NEW_VERSION/g" "$PROJECT_ROOT/README.md" 2>/dev/null || true
fi

echo ""
echo "✅ Version updated to $NEW_VERSION"
echo ""
echo "Files updated:"
echo "  • Xcode project: $PBXPROJ"
[ -f "$PROJECT_ROOT/README.md" ] && echo "  • README.md"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit changes: git add . && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "  3. Tag release: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION'"
echo "  4. Push changes: git push origin main --tags"
