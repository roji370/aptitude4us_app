#!/bin/bash

# iOS Notification Configuration Verification Script
# Run this before building for App Store to verify everything is correct

echo "🔍 iOS Notification Configuration Verification"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: Run this script from the project root${NC}"
    exit 1
fi

echo "📋 Checking Entitlements Files..."
echo ""

# Check Debug entitlements (should be development)
DEBUG_ENV=$(grep -A1 "aps-environment" ios/Runner/Runner.entitlements | grep "string" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
if [ "$DEBUG_ENV" = "development" ]; then
    echo -e "${GREEN}✅ Debug entitlements: development (correct)${NC}"
else
    echo -e "${RED}❌ Debug entitlements: $DEBUG_ENV (should be development)${NC}"
fi

# Check Release entitlements (should be production)
RELEASE_ENV=$(grep -A1 "aps-environment" ios/Runner/RunnerRelease.entitlements | grep "string" | head -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
if [ "$RELEASE_ENV" = "production" ]; then
    echo -e "${GREEN}✅ Release entitlements: production (correct)${NC}"
else
    echo -e "${RED}❌ Release entitlements: $RELEASE_ENV (should be production)${NC}"
    echo -e "${YELLOW}   This will cause App Store notifications to fail!${NC}"
fi

echo ""
echo "📦 Checking Bundle ID..."
BUNDLE_ID=$(grep "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
echo "   Bundle ID: $BUNDLE_ID"
if [ "$BUNDLE_ID" = "com.briffini.academy" ]; then
    echo -e "${GREEN}✅ Bundle ID matches Firebase${NC}"
else
    echo -e "${YELLOW}⚠️  Verify this matches your Firebase app${NC}"
fi

echo ""
echo "📱 Checking Xcode Project Configuration..."

# Check if Push Notifications capability exists
if grep -q "com.apple.developer.aps-environment" ios/Runner/RunnerRelease.entitlements; then
    echo -e "${GREEN}✅ Push Notifications capability enabled${NC}"
else
    echo -e "${RED}❌ Push Notifications capability missing${NC}"
fi

# Check if Associated Domains capability exists
if grep -q "com.apple.developer.associated-domains" ios/Runner/RunnerRelease.entitlements; then
    echo -e "${GREEN}✅ Associated Domains capability enabled${NC}"
else
    echo -e "${YELLOW}⚠️  Associated Domains capability missing (may affect deep links)${NC}"
fi

echo ""
echo "🔥 Checking Firebase Configuration..."

if [ -f "ios/GoogleService-Info.plist" ]; then
    echo -e "${GREEN}✅ GoogleService-Info.plist exists${NC}"
    
    # Check bundle ID in GoogleService-Info.plist
    FIREBASE_BUNDLE=$(grep -A1 "BUNDLE_ID" ios/GoogleService-Info.plist | grep "string" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
    if [ "$FIREBASE_BUNDLE" = "com.briffini.academy" ]; then
        echo -e "${GREEN}✅ Firebase bundle ID matches${NC}"
    else
        echo -e "${RED}❌ Firebase bundle ID mismatch: $FIREBASE_BUNDLE${NC}"
    fi
else
    echo -e "${RED}❌ GoogleService-Info.plist missing${NC}"
fi

echo ""
echo "📝 Checking Info.plist..."

# Check that aps-environment is NOT in Info.plist (it should only be in entitlements)
if grep -q '<key>aps-environment</key>' ios/Runner/Info.plist; then
    if grep -A1 '<key>aps-environment</key>' ios/Runner/Info.plist | grep -q '<string>development</string>'; then
        echo -e "${RED}❌ aps-environment hardcoded in Info.plist (should only be in entitlements)${NC}"
    else
        echo -e "${YELLOW}⚠️  aps-environment found in Info.plist (check if it's commented out)${NC}"
    fi
else
    echo -e "${GREEN}✅ aps-environment not in Info.plist (correct - should only be in entitlements)${NC}"
fi

echo ""
echo "=============================================="
echo ""

# Final summary
if [ "$RELEASE_ENV" = "production" ]; then
    echo -e "${GREEN}🎉 Configuration looks good for App Store!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Clean and build: flutter clean && cd ios && pod install && cd .."
    echo "2. Build release: flutter build ios --release --build-number=8"
    echo "3. Archive in Xcode: open ios/Runner.xcworkspace"
    echo "4. Test on TestFlight before submitting to App Store"
    echo ""
    echo "See NOTIFICATION_TEST_GUIDE.md for detailed testing instructions"
else
    echo -e "${RED}⚠️  Configuration issues found!${NC}"
    echo ""
    echo "Fix the issues above before building for App Store"
    echo "Main issue: RunnerRelease.entitlements should have 'production' not '$RELEASE_ENV'"
fi

echo ""

