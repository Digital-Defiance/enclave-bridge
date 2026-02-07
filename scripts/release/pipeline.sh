set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}"/1-build-app.sh
"${SCRIPT_DIR}"/2-sign-app.sh
"${SCRIPT_DIR}"/3-notarize-app.sh
"${SCRIPT_DIR}"/4-create-dmg.sh

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DMG_NAME="Enclave Bridge"
DMG_FILE="$PROJECT_ROOT/build/${DMG_NAME}.dmg"
ZIP_FILE="$PROJECT_ROOT/build/${DMG_NAME}.zip"

echo "Moving ${DMG_FILE} to ${PROJECT_ROOT}"
mv "${DMG_FILE}" "$PROJECT_ROOT"

echo "Moving ${ZIP_FILE} to ${PROJECT_ROOT}"
mv "${ZIP_FILE}" "$PROJECT_ROOT"

"${SCRIPT_DIR}"/5-build-for-app-store.sh

echo "Moving dmg back to export folder"
mv "${PROJECT_ROOT}/${DMG_NAME}.dmg" "${PROJECT_ROOT}/build/export/"

echo "Moving zip back to export folder"
mv "${PROJECT_ROOT}/${DMG_NAME}.zip" "${PROJECT_ROOT}/build/export/"
