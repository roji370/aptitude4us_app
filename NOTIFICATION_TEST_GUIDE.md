# 🧪 iOS Notification Testing Guide - Before App Store Distribution

## 📋 Overview

This guide shows you how to thoroughly test iOS push notifications **before** submitting to the App Store, using TestFlight and local builds.

---

## ✅ What Was Fixed

### Issue
- **App Store builds** were using `development` APNs environment
- **Local Xcode builds** work because they use development certificates
- **Production builds** need `production` APNs environment

### Fix Applied
Updated `ios/Runner/RunnerRelease.entitlements`:
- Changed `aps-environment` from `development` to `production`
- Added all required capabilities for production notifications

---

## 🎯 Testing Strategy

You have **3 ways** to test notifications before App Store release:

### Method 1: TestFlight (Recommended) ⭐
**Most accurate** - Uses actual production environment

### Method 2: Local Release Build
**Faster** - Tests production configuration locally

### Method 3: Archive Build
**Developer testing** - Tests the exact build that goes to App Store

---

## 🚀 Method 1: TestFlight Testing (RECOMMENDED)

### Step 1: Build Release Version

```bash
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp

# Clean everything
flutter clean

# Clean iOS dependencies
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..

# Increment build number (current is 7, make it 8)
# This ensures App Store recognizes it as new build
flutter build ios --release --build-number=8
```

### Step 2: Archive in Xcode

```bash
# Open Xcode workspace
open ios/Runner.xcworkspace
```

**In Xcode:**
1. Select **Product** → **Destination** → **Any iOS Device (arm64)**
2. Select **Product** → **Archive**
3. Wait for archive to complete (~3-5 minutes)
4. Xcode Organizer opens automatically

### Step 3: Upload to TestFlight

**In Xcode Organizer:**
1. Click **Distribute App**
2. Select **App Store Connect**
3. Click **Upload**
4. Choose **Automatically manage signing** ✅
5. Review the app, click **Upload**
6. Wait for upload to complete (~10-20 minutes)

### Step 4: Add TestFlight Testers

**In App Store Connect:**
1. Go to https://appstoreconnect.apple.com
2. Navigate to **My Apps** → **Xfini Academy** (or your app name)
3. Click **TestFlight** tab
4. Wait for build to process (~5-15 minutes after upload)
5. Once processing complete, under **Internal Testing**:
   - Click **+** to add testers
   - Add your email(s)
   - Enable the new build
6. TestFlight invitation sent via email

### Step 5: Install TestFlight Build

**On your iPhone:**
1. Install **TestFlight** app from App Store (if not already)
2. Open invitation email
3. Click **View in TestFlight**
4. Click **Accept** → **Install**
5. Open the app

### Step 6: Test Notifications

#### A. Verify Token Registration

1. Open the app
2. Login with your account
3. Grant notification permissions when prompted
4. Keep app open for 10 seconds

**Check Firestore:**
- Open Firebase Console → Firestore Database
- Navigate to `user_tokens` collection
- Find document with your userId
- Verify:
  - `token` field exists (FCM token)
  - `platform` = "ios"
  - `lastUpdated` is recent timestamp

#### B. Send Test Notification from Firebase

**Firebase Console:**
1. Go to **Engage** → **Messaging**
2. Click **Create your first campaign** (or **New campaign**)
3. Select **Firebase Notification messages**
4. Fill in:
   - **Title**: "Test Notification"
   - **Text**: "Testing iOS notifications from TestFlight"
5. Click **Next**
6. Under **Target**:
   - Select **User segment**
   - Choose **iOS** platform
7. Click **Next** → **Review** → **Publish**

**Expected Result:**
- ✅ Notification appears on lock screen
- ✅ Notification appears in notification center
- ✅ Badge appears on app icon
- ✅ Sound plays
- ✅ Tapping notification opens app

#### C. Test Chat Notifications

1. Have someone send you a chat message
2. **Close the app** (swipe up to kill)
3. Wait for notification to arrive

**Expected Result:**
- ✅ Notification shows sender name and message preview
- ✅ Tapping opens chat screen
- ✅ Badge count increases

#### D. Test Course Update Notifications

1. As admin, publish a new course or update
2. **Close the student app**
3. Wait for notification

**Expected Result:**
- ✅ Notification shows course update
- ✅ Tapping opens course screen
- ✅ UI shows "NEW" indicators

---

## ⚡ Method 2: Local Release Build (Quick Test)

### Step 1: Build and Install

```bash
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp

# Connect iPhone via USB cable
# Make sure iPhone is unlocked

# Build and install in release mode
flutter run --release
```

### Step 2: Test Same as TestFlight

Follow **Step 6 (A, B, C, D)** from Method 1 above.

**Note:** This tests production APNs configuration but may have slight differences from actual App Store build.

---

## 🔍 Method 3: Archive Build Testing

### Build Archive Locally

```bash
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp

# Build archive
flutter build ios --release --build-number=8

# Open Xcode
open ios/Runner.xcworkspace
```

**In Xcode:**
1. Product → Destination → Your iPhone (connected via USB)
2. Product → Archive
3. After archive completes, click **Distribute App**
4. Select **Development**
5. Click **Next** → **Export**
6. Install the exported `.ipa` using tools like:
   - Apple Configurator
   - Xcode Devices window (drag & drop)

Then test as in Method 1, Step 6.

---

## 📊 Checklist Before App Store Submission

### ✅ Pre-Submission Tests

Run through this checklist:

- [ ] **TestFlight build installed successfully**
- [ ] **App launches without crashes**
- [ ] **Login works properly**
- [ ] **FCM token registered in Firestore** (`user_tokens` collection)
- [ ] **Test notification from Firebase Console received**
- [ ] **Chat notification received when app closed**
- [ ] **Chat notification opens correct chat**
- [ ] **Course update notification received**
- [ ] **Course update notification opens correct course**
- [ ] **Badge count increases correctly**
- [ ] **Badge clears when app opened**
- [ ] **Notification sound plays**
- [ ] **UI shows "NEW" indicators for course updates**
- [ ] **All other app features work (not broken by notification changes)**

### ✅ Firebase Configuration Verified

- [ ] **Firebase Console has Production APNs key uploaded**
  - Go to: Project Settings → Cloud Messaging → Apple app
  - Should show "APNs Authentication Key" with Key ID
- [ ] **Key is NOT expired**
- [ ] **Bundle ID matches**: `com.briffini.academy`

### ✅ Xcode Configuration Verified

Open `ios/Runner.xcworkspace`, select Runner target:

- [ ] **Signing & Capabilities** tab:
  - [ ] **Push Notifications** capability enabled
  - [ ] **Background Modes** enabled with **Remote notifications** checked
  - [ ] **Associated Domains** enabled
- [ ] **Build Settings** tab:
  - [ ] Release configuration uses `RunnerRelease.entitlements`
  - [ ] Code Signing Identity: "Apple Distribution"
  - [ ] Provisioning Profile: App Store profile

---

## 🐛 Troubleshooting

### Issue: Token Not Registered in Firestore

**Check:**
```bash
# View app logs
# In Xcode with device connected:
# Window → Devices and Simulators → Select your device → Open Console
# Filter by "FCM" or "APNs"
```

**Look for:**
- ✅ "FCM registration token: [token]"
- ✅ "APNs token now available"
- ❌ "APNs token not available"
- ❌ "Failed to get FCM token"

**Solution:**
- Ensure notification permissions granted
- Check internet connection
- Restart app
- Check Firestore security rules allow token writes

---

### Issue: Notification Not Received

**Check:**
1. **Device Settings** → **Notifications** → **Your App**
   - Allow Notifications: ON
   - Banners: ON
   - Sounds: ON
   - Badges: ON

2. **Firebase Console Message Status**
   - Check if message was sent successfully
   - Look for delivery confirmation

3. **APNs Key in Firebase**
   - Verify production key uploaded
   - Key must not be expired
   - Key must have correct permissions

**Solution:**
- Delete and reinstall app
- Re-grant notification permissions
- Check APNs key in Firebase Console
- Verify bundle ID matches everywhere

---

### Issue: Notifications Work in TestFlight but Not App Store

This **should not happen anymore** after the fix, but if it does:

**Possible causes:**
1. Wrong provisioning profile used
2. Archive configuration issue
3. Firebase APNs key issue

**Solution:**
1. Re-archive with correct configuration
2. Verify entitlements embedded in IPA:
   ```bash
   # Extract IPA
   unzip YourApp.ipa
   
   # Check entitlements
   codesign -d --entitlements :- Payload/YourApp.app
   ```
3. Should show `aps-environment = production`

---

## 📱 Testing Scenarios

### Scenario 1: App in Foreground
- **Action:** App is open and active
- **Expected:** Notification banner appears at top
- **Sound:** Plays
- **Badge:** Updates

### Scenario 2: App in Background
- **Action:** App minimized, home screen visible
- **Expected:** Notification appears in notification center
- **Sound:** Plays
- **Badge:** Updates

### Scenario 3: App Closed/Terminated
- **Action:** App fully closed (swiped away)
- **Expected:** Notification appears on lock screen
- **Sound:** Plays
- **Badge:** Updates
- **Tap:** Opens app to correct screen

### Scenario 4: Device Locked
- **Action:** Screen locked, device asleep
- **Expected:** Screen lights up with notification
- **Sound:** Plays
- **Badge:** Updates when screen unlocked

---

## 🎉 Ready for App Store Submission

Once all checklist items are ✅:

1. **Archive final build:**
   ```bash
   flutter build ios --release --build-number=8
   ```

2. **Submit via Xcode:**
   - Open Xcode Organizer
   - Select archive
   - Distribute App → App Store Connect → Upload

3. **Complete App Store Connect listing:**
   - Screenshots
   - Description
   - What's New text
   - Submit for review

4. **Monitor after approval:**
   - Watch crash reports
   - Monitor notification delivery rates
   - Check user feedback

---

## 📞 Support

If issues persist after following this guide:

1. **Check Firebase Console logs**
2. **Check Xcode device console logs**
3. **Verify Firestore security rules**
4. **Ensure production APNs key is valid**

---

**Implementation Date:** November 17, 2025  
**Status:** ✅ FIXED AND READY FOR TESTING  
**Next Step:** Follow Method 1 (TestFlight) for comprehensive testing

