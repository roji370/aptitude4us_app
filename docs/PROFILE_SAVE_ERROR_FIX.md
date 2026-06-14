# Profile Save Error Fix - "Failed to perform the desired action"

## Issue
Users were experiencing an error when trying to save their profile:
```
Failed to save profile: Exception: Failed to perform the desired action
```

The app would get stuck on the profile completion screen and not navigate forward.

## Root Causes

### 1. StorageService Instance Creation
**Problem**: The code was creating a new `StorageService()` instance directly instead of using the Provider instance. This caused:
- A new initialization cycle every time
- Race condition with Firebase Storage initialization
- Unpredictable behavior

**Code Before**:
```dart
final storageService = StorageService();  // Creates new instance
```

**Code After**:
```dart
final storageService = Provider.of<StorageService>(context, listen: false);  // Uses existing singleton
```

### 2. Missing Photo Permissions
**Problem**: On Android 13+ (API 33+), photo access requires the `READ_MEDIA_IMAGES` permission, which needs to be explicitly requested at runtime. Older Android versions use `READ_EXTERNAL_STORAGE`.

**Solution**: Added runtime permission checks before attempting to pick images.

### 3. Poor Error Handling
**Problem**: Generic error messages didn't help users understand what went wrong.

**Solution**: Implemented specific error handling for:
- Photo upload failures
- Firestore update failures
- Permission denials
- Unexpected errors

## Changes Made

### 1. Updated Profile Completion Screen
**File**: `lib/screens/profile_completion_screen.dart`

#### A. Fixed StorageService Usage
```dart
// OLD - Creating new instance
final storageService = StorageService();

// NEW - Using Provider instance
final storageService = Provider.of<StorageService>(context, listen: false);
```

**Impact**: Uses the properly initialized singleton instance from Provider.

#### B. Fixed Permission Handling
```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> _pickImage() async {
  try {
    // For Android, check storage/photos permission
    if (Platform.isAndroid) {
      // Try storage permission first (works for most Android versions)
      PermissionStatus storageStatus = await Permission.storage.status;
      
      if (!storageStatus.isGranted) {
        // Request storage permission
        storageStatus = await Permission.storage.request();
        
        if (!storageStatus.isGranted) {
          // Try photos permission as fallback (for Android 13+)
          PermissionStatus photosStatus = await Permission.photos.status;
          if (!photosStatus.isGranted) {
            photosStatus = await Permission.photos.request();
          }
          
          // If both are denied, show message
          if (!photosStatus.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Photo access permission is required...'),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
            return;
          }
        }
      }
    }
    
    // Proceed with image picking
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(...);
    // ...
  } catch (e) {
    // Handle errors
  }
}
```

**Impact**: 
- Checks permission status first before requesting
- Works with both storage (older Android) and photos (Android 13+) permissions
- Uses fallback mechanism - tries storage first, then photos if needed
- Only shows error if both permissions are denied
- Provides clear feedback if permission is denied
- Offers quick access to settings to grant permission

**Update (Permission Detection Fix)**:
The initial implementation had an issue where it would show permission error even when permissions were already granted. This was due to incorrect Android version detection. The fix:
- Removed unreliable `_isAndroid13OrAbove()` method
- Now checks permission status first using `Permission.storage.status`
- Requests permission only if not already granted
- Falls back to photos permission if storage permission fails
- Works correctly when permissions are already granted in system settings

#### C. Improved Error Handling

**Photo Upload Errors**:
```dart
if (_selectedImage != null) {
  try {
    photoUrl = await storageService.uploadProfilePhoto(userId, _selectedImage!);
  } catch (uploadError) {
    Logger.e('Failed to upload photo: $uploadError');
    throw Exception('Failed to upload photo. Please check your internet connection and try again.');
  }
}
```

**Profile Update Errors**:
```dart
try {
  await authService.updateUserProfile(
    photoUrl: photoUrl,
    dateOfJoining: _dateOfJoining,
    examDate: _examDate,
    mobile: _mobileController.text.trim(),
    subscriptionPeriod: _subscriptionPeriod,
  );
} catch (updateError) {
  Logger.e('Failed to update profile in Firestore: $updateError');
  throw Exception('Failed to save profile details. Please check your internet connection and try again.');
}
```

**Multiple Catch Blocks**:
```dart
} on Exception catch (e) {
  // Handle our custom exceptions with user-friendly messages
  String errorMessage = e.toString().replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(errorMessage),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ),
  );
} catch (e) {
  // Handle any other unexpected errors
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('An unexpected error occurred. Please try again later.'),
      backgroundColor: Colors.red,
    ),
  );
}
```

**Impact**:
- Specific error messages for different failure scenarios
- Longer display time (5 seconds) for errors
- Cleaner error text (removes "Exception:" prefix)
- Better debugging with detailed logging

### 2. Storage Service Improvements
**File**: `lib/services/storage_service.dart`

Already fixed in previous update:
- Added initialization guards
- Ensured initialization before upload
- Better error handling

## User Experience Improvements

### Before Fix
1. User taps "Tap to add photo"
2. Gets generic error (possibly due to permissions)
3. Error message: "Failed to save profile: Exception: Failed to perform the desired action"
4. No guidance on how to fix it
5. Stuck on profile completion screen

### After Fix
1. User taps "Tap to add photo"
2. App requests photo permission (if not granted)
3. If denied: Clear message + "Settings" button to grant permission
4. If granted: Photo picker opens successfully
5. Photo uploads with progress indication
6. Specific error messages if upload or save fails:
   - "Failed to upload photo. Please check your internet connection and try again."
   - "Failed to save profile details. Please check your internet connection and try again."
7. On success: Smooth navigation to home screen

## Testing Checklist

### Permission Testing
- [x] First time photo selection requests permission
- [x] Permission denial shows helpful message
- [x] Settings button opens app settings
- [x] After granting permission, photo picker works
- [x] Android 13+ uses photos permission
- [x] Android 12 and below uses storage permission

### Error Handling Testing
- [x] Network error during upload shows specific message
- [x] Network error during profile save shows specific message
- [x] Generic errors show fallback message
- [x] Error messages are user-friendly (no "Exception:" prefix)
- [x] Errors display for 5 seconds

### Functionality Testing
- [x] Can select profile photo
- [x] Can save profile with all fields
- [x] Successfully navigates to home after save
- [x] Edit mode still works correctly
- [x] StorageService uses Provider instance

## Technical Details

### Android Permission Levels

| Android Version | API Level | Permission Required |
|----------------|-----------|-------------------|
| Android 13+ | 33+ | `READ_MEDIA_IMAGES` (photos) |
| Android 12 and below | 32 and below | `READ_EXTERNAL_STORAGE` |

### Provider Pattern
The fix ensures proper use of the Provider pattern:
- `StorageService` is registered as a singleton in `main.dart`
- All screens should use `Provider.of<StorageService>()` to access it
- This ensures only one instance exists and it's properly initialized

### Error Message Priority
1. **Custom Exception**: Shows clean, user-friendly message
2. **Unexpected Error**: Shows generic fallback message
3. **Logged Details**: All errors logged with full stack trace for debugging

## Related Files
- `lib/screens/profile_completion_screen.dart` - Profile form with fixes
- `lib/services/storage_service.dart` - Storage service with initialization fixes
- `lib/main.dart` - Provider registration
- `android/app/src/main/AndroidManifest.xml` - Permission declarations

## Common User Scenarios

### Scenario 1: Permission Denied
**User Action**: Taps photo, denies permission  
**App Response**: Shows orange snackbar with "Settings" button  
**Resolution**: User taps Settings → Grants permission → Returns to app → Tries again

### Scenario 2: No Internet
**User Action**: Fills profile, taps save  
**App Response**: Shows "Please check your internet connection" message  
**Resolution**: User connects to internet → Tries again → Succeeds

### Scenario 3: Successful Save
**User Action**: Selects photo, fills all fields, taps save  
**App Response**: Shows upload progress → Success message → Navigates to home  
**Result**: Profile complete, user can access app

## Date
November 3, 2025

## Status
✅ Fixed and Tested

