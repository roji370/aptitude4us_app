# Date Format Fix Documentation

## Issue
The `dateOfJoining` and `examDate` fields in the user documents were being stored as integers (Unix timestamps in milliseconds) instead of proper Firestore Timestamp objects. This caused them to display as numbers in the Firebase Console rather than as formatted dates.

## Changes Made

### 1. Updated `lib/models/user_model.dart`
- **Added import**: `import 'package:cloud_firestore/cloud_firestore.dart';`
- **Updated `fromJson()` method**: Now checks for Firestore Timestamp type first, then falls back to int (for backward compatibility), then string
- **Updated `toJson()` method**: Now converts DateTime objects to Firestore Timestamps using `Timestamp.fromDate()`

```dart
// Old code (stored as milliseconds):
'dateOfJoining': dateOfJoining?.millisecondsSinceEpoch,
'examDate': examDate?.millisecondsSinceEpoch,

// New code (stores as Firestore Timestamp):
'dateOfJoining': dateOfJoining != null ? Timestamp.fromDate(dateOfJoining!) : null,
'examDate': examDate != null ? Timestamp.fromDate(examDate!) : null,
```

### 2. Updated `lib/services/auth_service.dart`
- **Updated `updateUserProfile()` method**: Now uses `Timestamp.fromDate()` instead of `millisecondsSinceEpoch`

```dart
// Old code:
updateData['dateOfJoining'] = dateOfJoining.millisecondsSinceEpoch;
updateData['examDate'] = examDate.millisecondsSinceEpoch;

// New code:
updateData['dateOfJoining'] = Timestamp.fromDate(dateOfJoining);
updateData['examDate'] = Timestamp.fromDate(examDate);
```

### 3. Created Migration Script
Created `migrate_dates.js` to convert existing data from milliseconds to Timestamp format.

## Benefits
1. ✅ Dates now display properly in Firebase Console as formatted dates (e.g., "May 18, 2025 at 8:26:39 PM UTC+5:30")
2. ✅ Better data type consistency with Firestore best practices
3. ✅ Backward compatibility maintained - can still read old integer format
4. ✅ More efficient querying and filtering in Firestore queries

## Migration Instructions

### Prerequisites
1. You need a Firebase service account key file for the migration script
2. Node.js must be installed on your system

### Step 1: Download Service Account Key
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings (gear icon) → Service accounts
4. Click "Generate new private key"
5. Save the JSON file as `serviceAccountKey.json` in the `firebase-functions` directory

### Step 2: Install Dependencies (if not already installed)
```bash
cd firebase-functions
npm install firebase-admin
cd ..
```

### Step 3: Run Migration Script
```bash
node migrate_dates.js
```

The script will:
- Connect to your Firestore database
- Find all user documents
- Convert any `dateOfJoining` and `examDate` fields that are stored as numbers to Timestamp objects
- Report progress and results

### Step 4: Verify Migration
1. Open Firebase Console
2. Go to Firestore Database
3. Check a user document that previously had number dates
4. Verify that `dateOfJoining` and `examDate` now show as proper formatted dates

## Testing
After migration, test the following:
1. **View existing user profiles** - dates should display correctly
2. **Create new user profile** - dates should be saved as Timestamps
3. **Update user profile** - dates should be updated as Timestamps
4. **Login flow** - ensure no errors when reading user data

## Rollback (if needed)
If you need to rollback to the old format:
1. Revert the changes in `user_model.dart` and `auth_service.dart`
2. The data in Firestore can stay as Timestamps - they will still be read correctly

## Important Notes
- ⚠️ **Run the migration script only once** to avoid unnecessary processing
- ⚠️ **Backup your Firestore data** before running the migration (optional but recommended)
- ✅ The app now supports both formats during reading, so users won't experience any disruption
- ✅ New profiles will automatically use the correct Timestamp format

## Example Before/After

### Before (Integer format):
```json
{
  "dateOfJoining": 1762626600000,
  "examDate": 1764268200000
}
```

### After (Timestamp format):
```json
{
  "dateOfJoining": "May 18, 2025 at 8:26:39 PM UTC+5:30",
  "examDate": "November 29, 2025 at 4:47:43 PM UTC+5:30"
}
```

## Future Development
All new user profiles and profile updates will automatically use the Firestore Timestamp format going forward.

