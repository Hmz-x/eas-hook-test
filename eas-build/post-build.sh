#!/bin/bash

set -e

echo "🚀 Starting post-build Firebase App Distribution upload..."
echo "🔍 Debug info:"
echo "  - EAS_BUILD_PLATFORM: $EAS_BUILD_PLATFORM"
echo "  - EAS_BUILD_PROFILE: $EAS_BUILD_PROFILE"
echo "  - EAS_BUILD_WORKINGDIR: $EAS_BUILD_WORKINGDIR"
echo "  - PWD: $(pwd)"

# Check if this is a preview build
if [ "$EAS_BUILD_PROFILE" != "preview" ]; then
  echo "⏭️  Skipping upload - not a preview build"
  exit 0
fi

echo "🔍 Searching for build artifacts..."
echo "📁 Current directory contents:"
ls -la

echo "📁 Searching for APK files:"
find . -name "*.apk" -type f 2>/dev/null || echo "No APK files found"

echo "📁 Searching for build directories:"
find . -type d -name "*build*" 2>/dev/null || echo "No build directories found"

echo "📁 Checking common Android build paths:"
for path in "android/app/build/outputs/apk" "build" "dist" ".expo" "android/app/build/outputs/apk/release" "android/app/build/outputs/apk/debug"; do
  if [ -d "$path" ]; then
    echo "  Found directory: $path"
    ls -la "$path" 2>/dev/null || true
  fi
done

# Install Firebase CLI if not already installed
if ! command -v firebase &> /dev/null; then
  echo "📦 Installing Firebase CLI..."
  npm install -g firebase-tools
fi

# Authenticate with Firebase using service account key
if [ -z "$FIREBASE_SERVICE_ACCOUNT_KEY" ]; then
  echo "❌ FIREBASE_SERVICE_ACCOUNT_KEY environment variable is required"
  exit 1
fi

echo "$FIREBASE_SERVICE_ACCOUNT_KEY" > /tmp/firebase-key.json
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/firebase-key.json

# More comprehensive search for build artifacts
echo "🔍 Comprehensive search for build files..."

if [ "$EAS_BUILD_PLATFORM" == "android" ]; then
  APP_ID="$FIREBASE_ANDROID_APP_ID"
  
  # Try multiple common locations for APK files
  POSSIBLE_PATHS=(
    "android/app/build/outputs/apk/**/*.apk"
    "android/app/build/outputs/apk/release/*.apk"
    "android/app/build/outputs/apk/debug/*.apk"
    "build/*.apk"
    "dist/*.apk"
    ".expo/*.apk"
    "*.apk"
  )
  
  BUILD_FILE=""
  for pattern in "${POSSIBLE_PATHS[@]}"; do
    echo "  Checking pattern: $pattern"
    for file in $pattern; do
      if [ -f "$file" ]; then
        BUILD_FILE="$file"
        echo "  ✅ Found APK: $BUILD_FILE"
        break 2
      fi
    done
  done
  
elif [ "$EAS_BUILD_PLATFORM" == "ios" ]; then
  APP_ID="$FIREBASE_IOS_APP_ID"
  
  # Try multiple common locations for IPA files
  POSSIBLE_PATHS=(
    "build/*.ipa"
    "dist/*.ipa"
    ".expo/*.ipa"
    "*.ipa"
  )
  
  BUILD_FILE=""
  for pattern in "${POSSIBLE_PATHS[@]}"; do
    echo "  Checking pattern: $pattern"
    for file in $pattern; do
      if [ -f "$file" ]; then
        BUILD_FILE="$file"
        echo "  ✅ Found IPA: $BUILD_FILE"
        break 2
      fi
    done
  done
else
  echo "❌ Unsupported platform: $EAS_BUILD_PLATFORM"
  exit 1
fi

if [ -z "$BUILD_FILE" ]; then
  echo "❌ Build file not found. Searched in:"
  for pattern in "${POSSIBLE_PATHS[@]}"; do
    echo "    $pattern"
  done
  echo "📁 Complete directory tree:"
  find . -type f -name "*.apk" -o -name "*.ipa" 2>/dev/null || echo "No APK or IPA files found anywhere"
  exit 1
fi

echo "📱 Found build file: $BUILD_FILE"
echo "📊 File info:"
ls -lh "$BUILD_FILE"

# Test Firebase authentication
echo "🔐 Testing Firebase authentication..."
firebase projects:list --project "$FIREBASE_PROJECT_ID" || {
  echo "❌ Firebase authentication failed"
  exit 1
}

# Upload to Firebase App Distribution
echo "☁️  Uploading to Firebase App Distribution..."

firebase appdistribution:distribute "$BUILD_FILE" \
  --app "$APP_ID" \
  --groups "testers" \
  --release-notes "Preview build from EAS - $(date)" \
  --project "$FIREBASE_PROJECT_ID" || {
  echo "❌ Firebase upload failed"
  exit 1
}

echo "✅ Successfully uploaded to Firebase App Distribution!"

# Clean up
rm -f /tmp/firebase-key.json
