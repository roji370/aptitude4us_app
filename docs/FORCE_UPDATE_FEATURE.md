# Force Update Feature Documentation

## Overview
The Force Update feature allows you to require users to update their app before they can continue using it. This is useful for:
- Critical bug fixes
- Security updates
- Breaking API changes
- Major feature releases that require all users to be on the same version

## Update Distribution Methods

### Android Users
- **Direct APK Download**: Download and install APK files directly from Firebase Storage
- **Play Store Redirect**: Fallback to Play Store if APK path is not configured
- See `ANDROID_APK_DOWNLOAD_UPDATE.md` for detailed APK distribution setup

### iOS Users
- **App Store Only**: Always redirects to the App Store (APK installation not supported on iOS)

## How It Works

1. **On App Launch**: The splash screen checks the current app version against the minimum required version stored in Firestore
2. **Version Comparison**: If the user's version is lower than the minimum required version, they're redirected to the Force Update screen
3. **Update Screen**: Users see a beautiful screen explaining the update is required with:
   - Current version number
   - Required version number
   - Custom update message
   - "Update Now" button that opens the app store

## Firestore Configuration

### Collection Structure
Create the following document in your Firestore database:

```
Collection: appConfig
Document ID: versionControl
```

### Document Fields

```javascript
{
  "minimumVersion": "1.0.5",           // String - Minimum version required to run the app
  "latestVersion": "1.0.6",            // String - Latest version available (optional, for reference)
  "forceUpdate": true,                  // Boolean - Enable/disable force update feature
  "updateMessage": "A new version...", // String - Custom message shown on update screen (optional)
  "apkDownloadPath": "app-updates/android/app-release-1.0.6.apk", // String - Firebase Storage path for Android APK (optional)
  "lastUpdated": Timestamp,             // Timestamp - When this was last updated (optional)
}
```

### Field Descriptions

- **minimumVersion** (Required): The minimum app version users must have to use the app
  - Format: "major.minor.patch" (e.g., "1.0.5")
  - Any version below this will trigger the force update screen

- **latestVersion** (Optional): The latest version available in stores
  - Used for reference/analytics
  - Not enforced by the app

- **forceUpdate** (Required): Master switch for the feature
  - `true`: Force update is enabled
  - `false`: Force update is disabled (users can use any version)

- **updateMessage** (Optional): Custom message shown on the force update screen
  - If not provided, default message is shown
  - Should explain why the update is important

- **apkDownloadPath** (Optional, Android only): Firebase Storage path to the APK file
  - Format: "folder/subfolder/filename.apk"
  - If provided, Android users will download APK directly from Firebase Storage
  - If empty or omitted, Android users will be redirected to Play Store
  - Ignored for iOS users (always redirected to App Store)
  - Example: "app-updates/android/app-release-1.0.6.apk"
  - See `ANDROID_APK_DOWNLOAD_UPDATE.md` for detailed setup

## Setting Up in Firestore

### Using Firebase Console

1. Go to Firebase Console → Firestore Database
2. Click "Start collection"
3. Collection ID: `appConfig`
4. Document ID: `versionControl`
5. Add the following fields:
   - `minimumVersion` (string): "1.0.5"
   - `forceUpdate` (boolean): true
   - `updateMessage` (string): "A new version of Xfini Academy is available. Please update to continue using the app."

### Example Document

```json
{
  "minimumVersion": "1.0.5",
  "latestVersion": "1.0.6",
  "forceUpdate": true,
  "updateMessage": "This update includes important security fixes and performance improvements. Please update to continue.",
  "lastUpdated": "2024-01-15T10:30:00Z"
}
```

## Version Number Format

Version numbers follow semantic versioning: `major.minor.patch`

Examples:
- `1.0.0` → `1.0.1` (patch update)
- `1.0.5` → `1.1.0` (minor update)
- `1.5.0` → `2.0.0` (major update)

The comparison logic:
- Compares major version first
- If equal, compares minor version
- If equal, compares patch version

## Updating the App Store Links

### Android (Play Store)
Edit `/lib/screens/force_update_screen.dart`, line ~20:
```dart
url = 'https://play.google.com/store/apps/details?id=com.briffini.academy';
```
Replace `com.briffini.academy` with your actual package name from `android/app/build.gradle`

### iOS (App Store)
Edit `/lib/screens/force_update_screen.dart`, line ~23:
```dart
url = 'https://apps.apple.com/app/id1234567890';
```
Replace `1234567890` with your actual App Store ID

## Testing the Feature

### Test Scenario 1: Force Update Disabled
1. In Firestore, set `forceUpdate: false`
2. Launch the app
3. Result: App should work normally regardless of version

### Test Scenario 2: Version is Current
1. In Firestore, set:
   - `forceUpdate: true`
   - `minimumVersion: "1.0.0"` (lower than current)
2. Launch the app
3. Result: App should work normally

### Test Scenario 3: Update Required
1. In Firestore, set:
   - `forceUpdate: true`
   - `minimumVersion: "2.0.0"` (higher than current)
2. Launch the app
3. Result: Force Update screen should appear

### Test Scenario 4: Firebase Error
1. Temporarily disconnect from internet
2. Launch the app
3. Result: App should continue to login (failsafe behavior)

## Current App Version

The current app version is defined in `pubspec.yaml`:
```yaml
version: 1.0.5+6
```
Format: `version+buildNumber`
- Version: 1.0.5 (semantic version shown to users)
- Build: 6 (internal build number)

## Deployment Checklist

When deploying a new version that requires forced update:

1. ☐ Update version in `pubspec.yaml`
2. ☐ Build and test the new version
3. ☐ Upload to Play Store / App Store
4. ☐ Wait for app store approval (iOS) and availability
5. ☐ Update Firestore `versionControl` document:
   - Set `minimumVersion` to the new required version
   - Update `latestVersion` (optional)
   - Update `updateMessage` with clear explanation
   - Keep `forceUpdate: true`
6. ☐ Monitor user updates through analytics

## Best Practices

1. **Gradual Rollout**: For major updates, consider:
   - Release the new version first
   - Wait a few days to ensure stability
   - Then update `minimumVersion` in Firestore

2. **Clear Communication**: Always provide a helpful `updateMessage` explaining:
   - Why the update is needed
   - What improvements it brings
   - How long it will take

3. **Emergency Rollback**: If a critical bug is found:
   - Set `forceUpdate: false` immediately
   - This allows users to continue using the app
   - Fix the bug and release a new version

4. **Version Strategy**:
   - Patch updates (1.0.x): Usually don't require force update
   - Minor updates (1.x.0): Force update if breaking changes
   - Major updates (x.0.0): Usually require force update

## Troubleshooting

### Issue: Force update screen doesn't appear
**Solutions**:
- Check Firestore document exists: `appConfig/versionControl`
- Verify `forceUpdate` is set to `true`
- Ensure `minimumVersion` is higher than app version
- Check app logs for version check errors

### Issue: Update button doesn't open store
**Solutions**:
- Verify app store URLs are correct in `force_update_screen.dart`
- Check device has internet connection
- Ensure URL launcher permissions are granted

### Issue: Can't access app after updating Firestore
**Solutions**:
- Set `forceUpdate: false` in Firestore
- Clear app data and reinstall
- Check if version comparison is correct

## Security Considerations

1. **Firestore Rules**: Ensure version control document is read-only for clients:
```javascript
match /appConfig/versionControl {
  allow read: if true;  // All users can read
  allow write: if false; // Only admins can write
}
```

2. **Graceful Degradation**: The feature fails gracefully:
   - If Firebase is unavailable → User can continue
   - If document doesn't exist → User can continue
   - If version check times out → User can continue

3. **Admin Only**: Only administrators should be able to modify version control settings

## Files Modified/Created

### New Files:
- `/lib/services/version_check_service.dart` - Version checking logic
- `/lib/screens/force_update_screen.dart` - Force update UI screen
- `/FORCE_UPDATE_FEATURE.md` - This documentation

### Modified Files:
- `/lib/screens/splash_screen.dart` - Added version check on startup
- `/pubspec.yaml` - Added `package_info_plus` dependency

## Support

For issues or questions about this feature, check:
- App logs in `/utils/logger.dart`
- Firestore console for configuration
- This documentation for setup guidance

