# ⚡ Quick Test Instructions - iOS Notifications

## ✅ Fix Applied
The App Store notification issue has been **FIXED**. Your release builds will now use production APNs.

---

## 🚀 Option 1: Quick Local Test (5 minutes)

**Best for**: Quick verification before TestFlight

```bash
# 1. Navigate to project
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp

# 2. Connect iPhone via USB

# 3. Build and run in release mode
flutter run --release
```

**Then test:**
1. Login to the app
2. Grant notification permissions
3. Close the app completely (swipe away)
4. Have someone send you a chat message
5. **Expected**: Notification appears ✅

---

## 🧪 Option 2: TestFlight Test (30 minutes)

**Best for**: Final verification before App Store

### Step 1: Build
```bash
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp
flutter clean
cd ios && pod install && cd ..
flutter build ios --release --build-number=8
```

### Step 2: Archive & Upload
```bash
open ios/Runner.xcworkspace
```

In Xcode:
1. Product → Archive (wait 3-5 min)
2. Distribute App → TestFlight → Upload
3. Wait for processing (~10-15 min)

### Step 3: Install from TestFlight
1. Open TestFlight app on iPhone
2. Install the new build
3. Open app, login, grant permissions

### Step 4: Test Notifications
1. **Close app completely**
2. Have someone send you a message
3. **Expected**: Notification appears ✅

---

## ✅ Quick Verification

Run this before building:
```bash
./verify_ios_config.sh
```

Should show:
- ✅ Release entitlements: production
- ✅ Bundle ID matches Firebase
- ✅ Push Notifications capability enabled

---

## 🐛 If Notifications Don't Work

### Check 1: Token Registration
1. Open Firebase Console → Firestore
2. Go to `user_tokens` collection
3. Find your userId document
4. Verify `token` field exists and `platform` = "ios"

### Check 2: Device Permissions
Settings → Notifications → [Your App] → All should be ON

### Check 3: Firebase APNs Key
1. Firebase Console → Project Settings → Cloud Messaging
2. Apple app configuration should show "APNs Authentication Key"
3. Must be **Production** key, not development
4. Key must not be expired

---

## 📊 Test Scenarios

| Scenario | Action | Expected Result |
|----------|--------|----------------|
| **Chat Message** | Close app, receive message | Notification appears, opens chat |
| **Course Update** | Admin publishes update | Notification appears, opens course |
| **Badge Count** | Receive notifications | Badge number increases |
| **Badge Clear** | Open app | Badge clears to 0 |
| **Foreground** | App open, receive message | Banner at top |

---

## 🎯 Before App Store Submission

- [ ] Tested on TestFlight
- [ ] Chat notifications work
- [ ] Course notifications work
- [ ] Badge count updates
- [ ] All other features work
- [ ] No crashes in testing

---

## 📞 Firebase Console Check

**IMPORTANT**: Verify production APNs key

1. Go to https://console.firebase.google.com
2. Select project: `course-c18bb`
3. Project Settings → Cloud Messaging → Apple app configuration
4. Should show: "APNs Authentication Key" with Key ID

**If only development key exists:**
- Generate production key from Apple Developer Portal
- Upload to Firebase Console
- Guide: https://firebase.google.com/docs/cloud-messaging/ios/certs

---

## 🎉 You're Ready!

Once TestFlight testing passes, you can submit to App Store with confidence.

**Files Changed:**
- `ios/Runner/RunnerRelease.entitlements` (production APNs enabled)

**No Code Changes**: Only configuration updated ✅

---

**Need detailed instructions?** See `NOTIFICATION_TEST_GUIDE.md`

**Fix Date**: November 17, 2025  
**Status**: ✅ READY FOR TESTING

