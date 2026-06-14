# Android APK Update - Quick Start Guide

## 🚀 Quick Setup (5 Minutes)

### Step 1: Build Your APK (2 min)
```bash
cd /path/to/briffiniApp
flutter clean
flutter build apk --release
```
APK location: `build/app/outputs/flutter-apk/app-release.apk`

### Step 2: Upload to Firebase Storage (1 min)
1. Open [Firebase Console](https://console.firebase.google.com/) → Storage
2. Create folder: `app-updates/android/`
3. Upload APK and rename to: `app-release-1.0.6.apk`
4. Click the file → Copy path (should be: `app-updates/android/app-release-1.0.6.apk`)

### Step 3: Update Firestore (1 min)
1. Open [Firebase Console](https://console.firebase.google.com/) → Firestore
2. Navigate to: `appConfig` → `versionControl`
3. Add/Update these fields:

| Field | Type | Value |
|-------|------|-------|
| `minimumVersion` | string | `"1.0.6"` |
| `forceUpdate` | boolean | `true` |
| `apkDownloadPath` | string | `"app-updates/android/app-release-1.0.6.apk"` |
| `updateMessage` | string | `"New update available with improvements!"` |

4. Click **Save**

### Step 4: Test (1 min)
1. Install OLD version on test device
2. Open app
3. You should see Force Update screen
4. Tap "Update Now"
5. Watch download progress
6. Approve installation when prompted

**✅ Done!** Your users will now download APKs directly.

---

## 📝 Important Notes

### APK Path Format
- ✅ Correct: `app-updates/android/app-release-1.0.6.apk`
- ❌ Wrong: `gs://bucket/app-updates/...`
- ❌ Wrong: `/app-updates/...`
- ❌ Wrong: `https://storage.googleapis.com/...`

**Just use the path relative to your Storage bucket root!**

### Storage Rules (One-Time Setup)
Go to Firebase Console → Storage → Rules:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /app-updates/{allPaths=**} {
      allow read: if true;  // Anyone can download
      allow write: if false; // Only admins upload
    }
  }
}
```

### Version Format
Must match format in `pubspec.yaml`:
```yaml
version: 1.0.6+7
```
Use `1.0.6` in Firestore (not the `+7` build number).

---

## 🔄 Update Workflow

### Every Time You Release a New Version:

1. **Update `pubspec.yaml`**
   ```yaml
   version: 1.0.7+8  # Increment version
   ```

2. **Build APK**
   ```bash
   flutter build apk --release
   ```

3. **Upload to Storage**
   - Upload to: `app-updates/android/app-release-1.0.7.apk`

4. **Update Firestore**
   - `minimumVersion`: `"1.0.7"`
   - `apkDownloadPath`: `"app-updates/android/app-release-1.0.7.apk"`

5. **Test on Device**

**That's it! Users will get the update.**

---

## ⚠️ Common Issues & Fixes

### Issue: "Download Failed"
**Fix**: 
- Check APK exists in Storage at exact path
- Verify Storage rules allow read
- Check device has internet

### Issue: "Installation Failed"  
**Fix**: 
- APK must be signed with same keystore
- Check device storage space
- Allow "Install from unknown sources"

### Issue: Goes to Play Store Instead
**Fix**:
- Verify `apkDownloadPath` is NOT empty
- Check path format (no `gs://` prefix)
- Android only (iOS always goes to App Store)

### Issue: Progress Stuck at 0%
**Fix**:
- Wait 30 seconds
- Check Firebase Storage rules
- Verify internet connection

---

## 📱 Platform Behavior

| Platform | APK Path Provided | Behavior |
|----------|-------------------|----------|
| Android | ✅ Yes | Downloads & installs APK |
| Android | ❌ No/Empty | Redirects to Play Store |
| iOS | ✅ or ❌ | Always App Store (iOS can't install APKs) |

---

## 🎯 Quick Reference

### Firestore Document
```
Collection: appConfig
Document: versionControl
```

### Required Fields
- `minimumVersion` (string): `"1.0.6"`
- `forceUpdate` (boolean): `true`
- `apkDownloadPath` (string): `"app-updates/android/app-release-1.0.6.apk"`

### Optional Fields  
- `updateMessage` (string): Custom message to show users
- `latestVersion` (string): For reference only

---

## 📚 Full Documentation

For complete details, see:
- **`ANDROID_APK_DOWNLOAD_UPDATE.md`** - Complete guide
- **`ANDROID_APK_UPDATE_IMPLEMENTATION_SUMMARY.md`** - Technical details
- **`FORCE_UPDATE_FEATURE.md`** - Force update overview

---

## ✅ Checklist

Before going live:
- [ ] APK built and signed with release keystore
- [ ] APK uploaded to Firebase Storage
- [ ] Storage rules allow read access
- [ ] Firestore document updated
- [ ] `apkDownloadPath` is correct (no typos!)
- [ ] Tested on real Android device
- [ ] Version numbers match (`pubspec.yaml` ↔ Firestore)
- [ ] Update message is user-friendly

---

**Need Help?** Check the full documentation or contact the dev team.

**Tip**: Keep `forceUpdate: false` initially to test with a small group, then switch to `true` for mandatory updates.

