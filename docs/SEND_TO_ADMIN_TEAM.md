# 🔴 URGENT: iOS Notifications Not Working - Fix Required

## 📋 Problem

**Status:** Chat and course notifications work on **Android** but **NOT on iOS**.

**Root Cause:** Cloud Functions are querying FCM tokens **without filtering by `appType: 'student'`**, which causes iOS notifications to fail.

---

## ✅ Student App Status

The student app is working correctly:
- ✅ iOS tokens are being registered properly in `user_tokens` collection
- ✅ All required fields present: `appType: "student"`, `platform: "iOS"`, `isActive: true`
- ✅ iOS app subscribes to correct topics: `"student_chat"`, `"notifications"`

**Issue is 100% on admin app side** - token queries need filters added.

---

## 🔧 Required Fixes

### Fix: Add `appType` Filter to Token Queries

You need to add `.where('appType', '==', 'student')` to **4 locations** in `functions/src/notifications.js`

---

## 📝 Exact Code Changes

### **Change 1: Line 253-257** (Direct Chat Messages)

**File:** `functions/src/notifications.js`  
**Function:** `sendChatNotification`

```javascript
// FIND THIS (around line 253):
const userTokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', receiverId)
  .where('isActive', '==', true)
  .get();

// CHANGE TO:
const userTokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', receiverId)
  .where('isActive', '==', true)
  .where('appType', '==', 'student')  // ← ADD THIS LINE
  .get();
```

---

### **Change 2: Line 135-154** (Broadcast Chat Messages)

**File:** `functions/src/notifications.js`  
**Function:** `sendChatNotification` (broadcast section)

```javascript
// FIND THIS (around line 140-145):
tokenPromises.push(
  admin.firestore()
    .collection('user_tokens')
    .where('userId', '==', studentId)
    .where('isActive', '==', true)
    .get()
);

// CHANGE TO:
tokenPromises.push(
  admin.firestore()
    .collection('user_tokens')
    .where('userId', '==', studentId)
    .where('isActive', '==', true)
    .where('appType', '==', 'student')  // ← ADD THIS LINE
    .get()
);
```

---

### **Change 3: Line 369-373** (General Push Notifications)

**File:** `functions/src/notifications.js`  
**Function:** `sendPushNotification`

```javascript
// FIND THIS (around line 369):
const userTokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', recipientId)
  .where('isActive', '==', true)
  .get();

// CHANGE TO:
const userTokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', recipientId)
  .where('isActive', '==', true)
  .where('appType', '==', 'student')  // ← ADD THIS LINE
  .get();
```

---

### **Change 4: Line 563-567** (Course Assignment Notifications)

**File:** `functions/src/notifications.js`  
**Function:** `sendCourseAssignmentNotification`

```javascript
// FIND THIS (around line 563):
const tokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', userId)
  .where('isActive', '==', true)
  .get();

// CHANGE TO:
const tokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', userId)
  .where('isActive', '==', true)
  .where('appType', '==', 'student')  // ← ADD THIS LINE
  .get();
```

---

## 🚀 Deployment Steps

After making the changes:

```bash
# 1. Navigate to functions directory
cd functions

# 2. Deploy Cloud Functions
firebase deploy --only functions

# 3. Wait for deployment to complete (~2-3 minutes)
```

---

## 🧪 Testing

After deployment:

### Test 1: Chat Notification
1. Send a chat message to a student with an iOS device
2. **Expected:** iOS device receives notification immediately
3. **Also verify:** Android still works (should not break)

### Test 2: Course Assignment
1. Assign a course to a student with iOS device
2. **Expected:** iOS receives "New Course Assigned" notification

### Test 3: Course Update
1. Update a course title or add a module
2. **Expected:** iOS receives update notification

---

## 📊 Why This Fix Works

**Before (Current):**
```javascript
// Gets ALL tokens (student app + admin app + old tokens)
.where('userId', '==', userId)
.where('isActive', '==', true)
```
**Problem:** Could return admin app tokens or invalid tokens, causing iOS to fail

**After (Fixed):**
```javascript
// Gets ONLY student app tokens
.where('userId', '==', userId)
.where('isActive', '==', true)
.where('appType', '==', 'student')
```
**Result:** Only queries valid student app tokens, iOS notifications work ✅

---

## ⏱️ Estimated Time

- **Code changes:** 10 minutes (add one line in 4 places)
- **Deployment:** 3 minutes (Firebase deploy)
- **Testing:** 2 minutes (send test notification)
- **Total:** ~15 minutes

---

## ✅ Success Criteria

After deploying:
- ✅ iOS devices receive chat notifications
- ✅ iOS devices receive course assignment notifications
- ✅ iOS devices receive course update notifications
- ✅ Android continues to work (no regression)

---

## 🆘 If Issues Persist

If notifications still don't work after these changes:

1. **Check Firebase Console Logs:**
   - Go to: https://console.firebase.google.com/project/course-c18bb/functions/logs
   - Look for errors related to iOS tokens
   - Share any errors you see

2. **Verify Token Query:**
   - Add logging after token query:
   ```javascript
   console.log(`Found ${userTokensSnapshot.size} student tokens`);
   console.log(`iOS tokens:`, userTokensSnapshot.docs
     .filter(doc => doc.data().platform === 'iOS')
     .map(doc => doc.data().token.substring(0, 20) + '...')
   );
   ```

3. **Check Specific User:**
   - Test with user ID: `KFrsPCjr35T7hzCJ5a9JVDZ4nKE2`
   - This user has confirmed iOS token in Firestore

---

## 📞 Contact

If you need clarification or encounter issues:
- Student app is ready and working correctly
- All changes are on admin/backend side only
- No changes needed in student app

---

## 🎯 Summary

**What:** Add `appType` filter to 4 token queries  
**Where:** `functions/src/notifications.js` (4 locations)  
**Time:** ~15 minutes  
**Result:** iOS notifications will work immediately after deployment

---

**Priority:** 🔴 **CRITICAL** - iOS users cannot receive notifications  
**Complexity:** ✅ **SIMPLE** - Just add one line in 4 places  
**Impact:** 🎉 **HIGH** - Fixes all iOS notification issues

