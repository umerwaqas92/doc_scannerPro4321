#!/bin/bash

# Generate Android Keystore for Flutter App Signing
# Usage: ./generate_keystore.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Android Keystore Generator for Flutter${NC}"
echo "=========================================="

# Check if keytool is available
if ! command -v keytool &> /dev/null; then
    echo -e "${RED}Error: keytool not found. Please make sure Java JDK is installed and in your PATH.${NC}"
    exit 1
fi

# Default values
DEFAULT_KEYSTORE_PATH="android/app/upload-keystore.jks"
DEFAULT_KEY_ALIAS="upload"
DEFAULT_KEYSTORE_PASSWORD="android"
DEFAULT_KEY_PASSWORD="android"

echo -e "${YELLOW}This script will generate a keystore for signing your Android app.${NC}"
echo ""

# Get keystore path
read -p "Enter keystore path [${DEFAULT_KEYSTORE_PATH}]: " KEYSTORE_PATH
KEYSTORE_PATH=${KEYSTORE_PATH:-$DEFAULT_KEYSTORE_PATH}

# Get key alias
read -p "Enter key alias [${DEFAULT_KEY_ALIAS}]: " KEY_ALIAS
KEY_ALIAS=${KEY_ALIAS:-$DEFAULT_KEY_ALIAS}

# Get keystore password
read -s -p "Enter keystore password [${DEFAULT_KEYSTORE_PASSWORD}]: " KEYSTORE_PASSWORD
echo ""
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-$DEFAULT_KEYSTORE_PASSWORD}

# Get key password (usually same as keystore password)
read -s -p "Enter key password [${KEY_PASSWORD:-$KEYSTORE_PASSWORD}]: " KEY_PASSWORD
echo ""
KEY_PASSWORD=${KEY_PASSWORD:-$KEYSTORE_PASSWORD}

# Create android directory if it doesn't exist
mkdir -p android/app

# Check if keystore already exists
if [ -f "$KEYSTORE_PATH" ]; then
    echo -e "${YELLOW}Warning: Keystore file already exists at ${KEYSTORE_PATH}${NC}"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}Generating keystore...${NC}"

# Generate keystore
keytool -genkeypair \
    -v \
    -keystore "$KEYSTORE_PATH" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias "$KEY_ALIAS" \
    -storepass "$KEYSTORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=Unknown, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=Unknown"

echo -e "${GREEN}Keystore generated successfully!${NC}"

# Create key.properties file
KEY_PROPERTIES_PATH="android/key.properties"
echo -e "${GREEN}Creating key.properties file...${NC}"

cat > "$KEY_PROPERTIES_PATH" << EOF
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=$KEYSTORE_PATH
EOF

echo -e "${GREEN}key.properties file created at: $KEY_PROPERTIES_PATH${NC}"

# Update build.gradle.kts to use the signing config
BUILD_GRADLE_PATH="android/app/build.gradle.kts"

if [ -f "$BUILD_GRADLE_PATH" ]; then
    echo -e "${GREEN}Updating build.gradle.kts...${NC}"

    # Create backup
    cp "$BUILD_GRADLE_PATH" "${BUILD_GRADLE_PATH}.backup"

    # Add signing config and update release build type
    # This is a complex operation, so let's do it step by step

    # First, check if signingConfigs block exists
    if ! grep -q "signingConfigs" "$BUILD_GRADLE_PATH"; then
        # Add signingConfigs block before buildTypes
        sed -i '' '/buildTypes {/i\
    signingConfigs {\
        create("release") {\
            storeFile = file(System.getenv("KEYSTORE_PATH") ?: "upload-keystore.jks")\
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: "android"\
            keyAlias = System.getenv("KEY_ALIAS") ?: "upload"\
            keyPassword = System.getenv("KEY_PASSWORD") ?: "android"\
        }\
    }\
\
' "$BUILD_GRADLE_PATH"
    fi

    # Update release build type to use release signing config
    sed -i '' 's/signingConfig = signingConfigs.getByName("debug")/signingConfig = signingConfigs.getByName("release")/' "$BUILD_GRADLE_PATH"

    echo -e "${GREEN}build.gradle.kts updated successfully!${NC}"
    echo -e "${YELLOW}Backup created at: ${BUILD_GRADLE_PATH}.backup${NC}"
else
    echo -e "${YELLOW}Warning: build.gradle.kts not found. You need to manually update your build.gradle.kts file.${NC}"
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Add the key.properties file to your .gitignore"
echo "2. Set environment variables for CI/CD or keep the defaults"
echo "3. Run: flutter build apk --release"
echo ""
echo -e "${YELLOW}Important: Keep your keystore file and passwords secure!${NC}"