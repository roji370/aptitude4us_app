# Android APK Download & Update Feature

## Overview
This feature allows Android users to download and install APK updates directly from Firebase Storage, bypassing the Google Play Store. This is ideal for:
- Direct APK distribution outside Play Store
- Beta testing programs
- Enterprise/internal deployments
- Faster update rollouts

## How It Works

### User Experience
1. **App Launch**: The splash screen checks the app version against Firestore
2. **Update Detection**: If a new version is required, the Force Update screen appears
3. **Download**: User taps "Update Now" to download the APK from Firebase Storage
4. **Progress**: A progress bar shows download status with percentage
5. **Installation**: After download completes, Android's APK installer opens automatically
6. **User Approval**: User approves the installation (Android security requirement)

### For iOS Users
iOS users will still be redirected to the App Store (APK installation is Android-only).

## Firebase Storage Setup

### Step 1: Upload APK to Firebase Storage

1. **Build Your APK**
   ```bash
   flutter build apk --release
   ```
   The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

2. **Upload to Firebase Storage**
   - Open Firebase Console → Storage
   - Create a folder structure (recommended): `app-updates/android/`
   - Upload your APK file
   - Example path: `app-updates/android/app-release-1.0.6.apk`

3. **Set Storage Rules** (Important!)
   ```javascript
   rules_version = '2';
   service firebase.storage {
     match /b/{bucket}/o {
       // Allow anyone to read app updates
       match /app-updates/{allPaths=**} {
         allow read: if true;
         allow write: if false; // Only admins can upload
       }
     }
   }
   ```

### Step 2: Update Firestore Configuration

Update the `appConfig/versionControl` document in Firestore:

```json
{
  "minimumVersion": "1.0.6",
  "latestVersion": "1.0.6",
  "forceUpdate": true,
  "updateMessage": "A new version with improved features is available!",
  "apkDownloadPath": "app-updates/android/app-release-1.0.6.apk"
}
```

#### Field Descriptions

- **apkDownloadPath** (Required for Android): Firebase Storage path to the APK file
  - Format: `folder/subfolder/filename.apk`
  - Do NOT include `gs://bucket-name/` prefix
  - Example: `app-updates/android/app-release-1.0.6.apk`

All other fields remain the same as before (see `FORCE_UPDATE_FEATURE.md`).

## Android Permissions

The following permissions are automatically configured in `AndroidManifest.xml`:

```xml
<!-- Permission to install APK files (Android 8.0+) -->
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>

<!-- Internet access for downloading -->
<uses-permission android:name="android.permission.INTERNET"/>

<!-- Storage access for saving APK -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

## Testing the Feature

### Test Scenario 1: APK Download for Android
1. In Firestore, set:
   ```json
   {
     "minimumVersion": "2.0.0",
     "forceUpdate": true,
     "apkDownloadPath": "app-updates/android/your-apk-name.apk",
     "updateMessage": "Test update available"
   }
   ```
2. Ensure the APK exists at the specified path in Firebase Storage
3. Launch the app on an Android device
4. Result: Force Update screen appears with download button
5. Tap "Update Now"
6. Result: Download progress shown, then Android installer opens

### Test Scenario 2: Fallback to Play Store
1. In Firestore, set:
   ```json
   {
     "minimumVersion": "2.0.0",
     "forceUpdate": true,
     "apkDownloadPath": ""
   }
   ```
   (Empty or omit `apkDownloadPath`)
2. Launch the app
3. Result: Update button redirects to Play Store

### Test Scenario 3: iOS Behavior
1. Same configuration as Test Scenario 1
2. Launch the app on an iOS device
3. Result: Update button redirects to App Store (APK path is ignored)

## Security Considerations

### 1. Firebase Storage Rules
**CRITICAL**: Ensure your storage rules are properly configured:

```javascript
// ✅ CORRECT - Anyone can read, only admins can write
match /app-updates/{allPaths=**} {
  allow read: if true;
  allow write: if false;
}

// ❌ WRONG - Anyone can write
match /app-updates/{allPaths=**} {
  allow read, write: if true;
}
```

### 2. APK Signing
- Always sign your APKs with your release keystore
- Never distribute unsigned or debug APKs
- Users cannot install an APK with a different signature

### 3. Version Verification
The app verifies:
- Current version vs. minimum required version
- APK download URL from Firestore (not hardcoded)
- Permission status before downloading

### 4. HTTPS Only
- All downloads use HTTPS (Firebase Storage enforces this)
- No plaintext HTTP connections

## Troubleshooting

### Issue: "Download Failed"
**Possible Causes:**
- APK file doesn't exist in Firebase Storage
- Storage path is incorrect in Firestore
- Storage rules don't allow read access
- Network connection issues

**Solutions:**
1. Verify the APK exists: Firebase Console → Storage → Check path
2. Check `apkDownloadPath` in Firestore matches exactly
3. Review Storage rules
4. Check device internet connection

### Issue: "Installation Failed"
**Possible Causes:**
- APK signature mismatch (different keystore used)
- Insufficient storage space
- User denied installation permission
- Corrupted APK download

**Solutions:**
1. Ensure APK is signed with the same keystore as the currently installed app
2. Free up storage space on device
3. Grant installation permission when prompted
4. Re-download the APK

### Issue: "Permission Denied"
**Possible Causes:**
- User denied REQUEST_INSTALL_PACKAGES permission
- Installation from unknown sources disabled (Android < 8.0)

**Solutions:**
1. Settings → Apps → Your App → Allow from this source (Android 8.0+)
2. Settings → Security → Unknown Sources (Android < 8.0)

### Issue: Progress Stuck at 0%
**Possible Causes:**
- Firebase Storage download URL expired
- Network timeout
- Storage rules blocking access

**Solutions:**
1. Wait 30 seconds for timeout
2. Restart the app
3. Check Firebase Storage rules
4. Check device network connection

## Deployment Workflow

### For New Version Release

1. **Update App Version**
   - Edit `pubspec.yaml`:
     ```yaml
     version: 1.0.6+7  # Increment version
     ```

2. **Build Release APK**
   ```bash
   flutter clean
   flutter build apk --release
   ```

3. **Upload to Firebase Storage**
   - Go to Firebase Console → Storage
   - Upload to: `app-updates/android/app-release-1.0.6.apk`
   - Note: Include version number in filename for tracking

4. **Update Firestore**
   - Go to Firestore → `appConfig/versionControl`
   - Update fields:
     ```json
     {
       "minimumVersion": "1.0.6",
       "latestVersion": "1.0.6",
       "forceUpdate": true,
       "apkDownloadPath": "app-updates/android/app-release-1.0.6.apk",
       "updateMessage": "Version 1.0.6 includes bug fixes and new features!"
     }
     ```

5. **Test on Device**
   - Install old version on test device
   - Launch app
   - Verify update prompt appears
   - Complete download and installation
   - Verify new version works correctly

6. **Monitor Updates**
   - Track download success rate
   - Monitor error logs in Logger
   - Check user feedback

### Gradual Rollout Strategy

For critical updates, consider a gradual rollout:

**Phase 1: Beta Testing**
```json
{
  "minimumVersion": "1.0.5",  // Old version still allowed
  "latestVersion": "1.0.6",    // New version available
  "forceUpdate": false,         // Optional update
  "apkDownloadPath": "app-updates/android/app-release-1.0.6.apk"
}
```

**Phase 2: Mandatory After Testing**
```json
{
  "minimumVersion": "1.0.6",   // Require new version
  "forceUpdate": true          // Mandatory update
}
```

## File Structure

### New Files Created
```
lib/services/apk_download_service.dart    - APK download & install logic
ANDROID_APK_DOWNLOAD_UPDATE.md            - This documentation
```

### Modified Files
```
lib/screens/force_update_screen.dart      - Added download UI & logic
lib/screens/splash_screen.dart            - Pass APK path to update screen
android/app/src/main/AndroidManifest.xml  - Added install permission
pubspec.yaml                              - Added dio, install_plugin packages
```

## Dependencies Added

```yaml
dio: ^5.4.0                    # HTTP client for download with progress
install_plugin: ^2.1.0         # APK installation support
```

## Advanced Configuration

### Custom Download Directory

By default, APKs are downloaded to the app's temporary directory. To customize:

Edit `lib/services/apk_download_service.dart`:

```dart
// Current (temp directory)
final tempDir = await getTemporaryDirectory();
final savePath = '${tempDir.path}/app-update.apk';

// Custom (Downloads folder - requires additional permissions)
final downloadsDir = await getExternalStorageDirectory();
final savePath = '${downloadsDir.path}/Download/YourAppName/update.apk';
```

### Download Retry Logic

To add retry logic for failed downloads:

```dart
int maxRetries = 3;
int currentRetry = 0;

while (currentRetry < maxRetries) {
  try {
    await _apkDownloadService.downloadApk(...);
    break; // Success
  } catch (e) {
    currentRetry++;
    if (currentRetry >= maxRetries) {
      // Show error
    } else {
      await Future.delayed(Duration(seconds: 2));
    }
  }
}
```

### Background Download

Currently, download happens in foreground. For background download:

1. Consider using `flutter_downloader` package
2. Add foreground service for Android 9+
3. Show persistent notification during download

## Best Practices

### 1. Version Naming
```
app-release-1.0.6.apk   ✅ Good - includes version
app-release.apk         ❌ Bad - no version tracking
```

### 2. Storage Organization
```
app-updates/
  ├── android/
  │   ├── app-release-1.0.5.apk
  │   ├── app-release-1.0.6.apk
  │   └── beta/
  │       └── app-beta-1.0.7.apk
  └── release-notes/
      └── 1.0.6.txt
```

### 3. Update Messages
```
✅ Good: "Version 1.0.6 includes bug fixes, improved performance, and new chat features!"
❌ Bad: "Update available"
```

### 4. File Size Considerations
- Optimize APK size: `flutter build apk --split-per-abi`
- This creates separate APKs for arm64-v8a, armeabi-v7a, x86_64
- Smaller download size for users
- Need to handle multiple APK paths in Firestore

### 5. Cleanup Old APKs
- Regularly remove old APK files from Storage
- Keep last 2-3 versions for rollback capability
- Update `apkDownloadPath` in Firestore when changing

## FAQ

**Q: Can users skip the update?**
A: No, if `forceUpdate: true`, the update is mandatory. The user cannot proceed without updating.

**Q: What happens if download is interrupted?**
A: The download will fail, and user can tap "Update Now" again to retry.

**Q: Can I distribute different APKs to different users?**
A: Yes, by using different Firestore documents based on user groups or using Cloud Functions for dynamic routing.

**Q: How do I handle split APKs (per-ABI)?**
A: Either upload the universal APK, or use Cloud Functions to detect device architecture and return appropriate APK path.

**Q: Does this work with App Bundles (.aab)?**
A: No, only APK files can be installed directly. App Bundles require Play Store.

**Q: Can I track download analytics?**
A: Yes, add analytics events in `apk_download_service.dart` at key points (start, progress, complete, error).

## Support & Monitoring

### Log Messages
All operations are logged with emojis for easy identification:

```
🔄 Starting APK download from: ...
📥 Download URL obtained: ...
📊 Download progress: 45.2%
✅ APK downloaded successfully
📱 Installing APK from: ...
✅ APK installation initiated successfully
❌ Error: ...
```

### Monitoring in Production
Check logs for:
- Download success rate
- Common error patterns
- Average download time
- Installation success rate

## Migration from Play Store Distribution

If you're currently using Play Store and want to switch to direct APK:

1. Keep Play Store listing active initially
2. Add `apkDownloadPath` to Firestore (but keep it empty)
3. Test with beta users by providing them the APK path
4. Once stable, update `apkDownloadPath` in Firestore for all users
5. Users on old versions will be redirected to Play Store
6. Users on new versions will download APKs directly

## Related Documentation

- `FORCE_UPDATE_FEATURE.md` - Base force update feature
- `DEPLOYMENT_INSTRUCTIONS.md` - General deployment guide
- Firebase Storage Documentation
- Android APK Installation Documentation

## Version History

- **1.0.0** (Initial): Basic force update with Play Store redirect
- **1.0.6** (Current): Added direct APK download from Firebase Storage

---

For questions or issues, check the app logs or contact the development team.

