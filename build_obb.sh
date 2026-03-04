#!/bin/bash

# Build OBB (APK Expansion) File for Flutter Android App
# Usage: ./build_obb.sh [version_code]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Android OBB Builder for Flutter${NC}"
echo "=================================="

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter not found. Please make sure Flutter is installed and in your PATH.${NC}"
    exit 1
fi

# Get version code from pubspec.yaml or command line argument
if [ $# -eq 1 ]; then
    VERSION_CODE=$1
else
    # Extract version code from pubspec.yaml
    PUBSPEC_FILE="pubspec.yaml"
    if [ -f "$PUBSPEC_FILE" ]; then
        VERSION_LINE=$(grep "^version:" "$PUBSPEC_FILE")
        if [[ $VERSION_LINE =~ ([0-9]+)\+([0-9]+) ]]; then
            VERSION_CODE=${BASH_REMATCH[2]}
            echo -e "${BLUE}Using version code from pubspec.yaml: $VERSION_CODE${NC}"
        else
            echo -e "${YELLOW}Could not extract version code from pubspec.yaml${NC}"
            read -p "Enter version code: " VERSION_CODE
        fi
    else
        read -p "Enter version code: " VERSION_CODE
    fi
fi

# Validate version code
if ! [[ "$VERSION_CODE" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Version code must be a number${NC}"
    exit 1
fi

echo -e "${BLUE}Using version code: $VERSION_CODE${NC}"

# Get application ID from build.gradle.kts
BUILD_GRADLE="android/app/build.gradle.kts"
if [ -f "$BUILD_GRADLE" ]; then
    APPLICATION_ID=$(grep "applicationId.*=" "$BUILD_GRADLE" | head -1 | sed 's/.*applicationId = "\(.*\)".*/\1/' | tr -d '"')
    if [ -z "$APPLICATION_ID" ]; then
        APPLICATION_ID="come.alnomily.docts_scanner"
        echo -e "${YELLOW}Could not extract applicationId from build.gradle.kts, using default: $APPLICATION_ID${NC}"
    else
        echo -e "${BLUE}Using application ID: $APPLICATION_ID${NC}"
    fi
else
    APPLICATION_ID="come.alnomily.docts_scanner"
    echo -e "${YELLOW}build.gradle.kts not found, using default application ID: $APPLICATION_ID${NC}"
fi

# OBB file names
MAIN_OBB="${APPLICATION_ID}.obb"
PATCH_OBB="${APPLICATION_ID}.patch.obb"

# Directories
ANDROID_DIR="android"
ASSETS_DIR="android/app/src/main/assets"
OBB_DIR="android/obb"
OUTPUT_DIR="build/app/outputs/obb/release"

echo ""
echo -e "${GREEN}Checking app size...${NC}"

# Clean previous build
echo -e "${BLUE}Cleaning previous build...${NC}"
flutter clean

# Build APK to check size
echo -e "${BLUE}Building APK to check size...${NC}"
flutter build apk --release

APK_SIZE=$(stat -f%z "build/app/outputs/flutter-apk/app-release.apk" 2>/dev/null || echo "0")
APK_SIZE_MB=$((APK_SIZE / 1024 / 1024))

echo -e "${BLUE}APK size: ${APK_SIZE_MB}MB${NC}"

if [ "$APK_SIZE_MB" -lt 100 ]; then
    echo -e "${YELLOW}Warning: APK size is ${APK_SIZE_MB}MB, which is under 100MB.${NC}"
    echo -e "${YELLOW}OBB files are only needed for apps larger than 100MB.${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}Setting up OBB structure...${NC}"

# Create assets directory if it doesn't exist
mkdir -p "$ASSETS_DIR"

# Create OBB directory structure
mkdir -p "$OBB_DIR/main"
mkdir -p "$OBB_DIR/patch"

# Create sample content for main OBB (you would replace this with your actual large assets)
echo -e "${BLUE}Creating sample OBB content...${NC}"

# For main OBB - typically contains graphics, videos, large data files
MAIN_CONTENT_DIR="$OBB_DIR/main/assets"
mkdir -p "$MAIN_CONTENT_DIR"

# Create a placeholder file (replace with your actual content)
echo "This is the main OBB content placeholder." > "$MAIN_CONTENT_DIR/placeholder.txt"
echo "Add your large assets (images, videos, data files) here." >> "$MAIN_CONTENT_DIR/placeholder.txt"

# For patch OBB - typically contains updates and additional content
PATCH_CONTENT_DIR="$OBB_DIR/patch/assets"
mkdir -p "$PATCH_CONTENT_DIR"

echo "This is the patch OBB content placeholder." > "$PATCH_CONTENT_DIR/placeholder.txt"
echo "Add your patch content and updates here." >> "$PATCH_CONTENT_DIR/placeholder.txt"

echo -e "${YELLOW}Note: Replace the placeholder files with your actual large assets.${NC}"

# Create OBB files using job (if available) or zip
echo ""
echo -e "${GREEN}Creating OBB files...${NC}"

MAIN_OBB_FILE="main.$VERSION_CODE.$APPLICATION_ID.obb"
PATCH_OBB_FILE="patch.$VERSION_CODE.$APPLICATION_ID.obb"

# Check if jobb tool is available (Android SDK build-tools)
JOBB_PATH="$ANDROID_HOME/build-tools/*/jobb"
if compgen -G "$JOBB_PATH" > /dev/null; then
    JOBB_TOOL=$(ls -t $ANDROID_HOME/build-tools/*/jobb | head -1)
    echo -e "${BLUE}Using jobb tool: $JOBB_TOOL${NC}"

    # Create main OBB
    "$JOBB_TOOL" -d "$OBB_DIR/main" -o "$OUTPUT_DIR/$MAIN_OBB_FILE" -pn "$APPLICATION_ID" -pv $VERSION_CODE

    # Create patch OBB (if you have patch content)
    if [ -d "$OBB_DIR/patch" ] && [ "$(ls -A $OBB_DIR/patch)" ]; then
        "$JOBB_TOOL" -d "$OBB_DIR/patch" -o "$OUTPUT_DIR/$PATCH_OBB_FILE" -pn "$APPLICATION_ID" -pv $VERSION_CODE -pt patch
    fi
else
    echo -e "${YELLOW}jobb tool not found, using zip to create OBB files...${NC}"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Create main OBB using zip
    cd "$OBB_DIR/main"
    zip -r "../../$OUTPUT_DIR/$MAIN_OBB_FILE" .
    cd ../..

    # Create patch OBB using zip (if patch content exists)
    if [ -d "$OBB_DIR/patch" ] && [ "$(ls -A $OBB_DIR/patch)" ]; then
        cd "$OBB_DIR/patch"
        zip -r "../../$OUTPUT_DIR/$PATCH_OBB_FILE" .
        cd ../..
    fi
fi

# Verify OBB files were created
if [ -f "$OUTPUT_DIR/$MAIN_OBB_FILE" ]; then
    MAIN_OBB_SIZE=$(stat -f%z "$OUTPUT_DIR/$MAIN_OBB_FILE" 2>/dev/null || echo "0")
    MAIN_OBB_SIZE_MB=$((MAIN_OBB_SIZE / 1024 / 1024))
    echo -e "${GREEN}Main OBB created: $OUTPUT_DIR/$MAIN_OBB_FILE (${MAIN_OBB_SIZE_MB}MB)${NC}"
else
    echo -e "${RED}Error: Main OBB file was not created${NC}"
    exit 1
fi

if [ -f "$OUTPUT_DIR/$PATCH_OBB_FILE" ]; then
    PATCH_OBB_SIZE=$(stat -f%z "$OUTPUT_DIR/$PATCH_OBB_FILE" 2>/dev/null || echo "0")
    PATCH_OBB_SIZE_MB=$((PATCH_OBB_SIZE / 1024 / 1024))
    echo -e "${GREEN}Patch OBB created: $OUTPUT_DIR/$PATCH_OBB_FILE (${PATCH_OBB_SIZE_MB}MB)${NC}"
fi

# Update AndroidManifest.xml to include OBB permissions if not already present
MANIFEST_FILE="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST_FILE" ]; then
    if ! grep -q "com.android.vending.expansion" "$MANIFEST_FILE"; then
        echo -e "${BLUE}Adding OBB permissions to AndroidManifest.xml...${NC}"

        # Add expansion file permissions
        sed -i '' '/<\/manifest>/i\
    <!-- OBB Expansion File Permissions -->\
    <uses-permission android:name="com.android.vending.CHECK_LICENSE" />\
' "$MANIFEST_FILE"

        echo -e "${GREEN}OBB permissions added to AndroidManifest.xml${NC}"
    fi
fi

echo ""
echo -e "${GREEN}OBB build complete!${NC}"
echo ""
echo "Files created:"
echo "  - Main OBB: $OUTPUT_DIR/$MAIN_OBB_FILE"
if [ -f "$OUTPUT_DIR/$PATCH_OBB_FILE" ]; then
    echo "  - Patch OBB: $OUTPUT_DIR/$PATCH_OBB_FILE"
fi
echo ""
echo "Next steps:"
echo "1. Replace placeholder content in $OBB_DIR/ with your actual assets"
echo "2. Upload OBB files to Google Play Console along with your APK"
echo "3. Implement OBB downloading and mounting in your app code"
echo "4. Test the OBB download functionality"
echo ""
echo -e "${YELLOW}Note: OBB files must be uploaded to Google Play Console and downloaded by your app at runtime.${NC}"