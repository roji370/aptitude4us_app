# 🚀 Deployment Instructions - Notification Fixes & Content Updates

**Date:** November 5, 2025  
**Status:** Ready to Deploy

---

## 📦 What Needs to Be Deployed

### 1. ✅ Notification Fix (Student App - Flutter)
- Fixed FCM token storage structure
- Added missing topic subscriptions
- Added notification handlers

### 2. ✅ Content Update System (Backend - Cloud Functions)
- New cloud functions for detecting course/module updates
- Firestore security rules
- Automated notification system

---

## 🔄 Deployment Steps

### STEP 1: Deploy Backend (Cloud Functions + Rules)

```bash
# Navigate to project root
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp

# Deploy cloud functions
cd firebase-functions
firebase deploy --only functions

# Expected output:
# ✔ functions[notifyCourseUpdate(us-central1)] Successful update operation.
# ✔ functions[notifyModuleUpdate(us-central1)] Successful update operation.
# ✔ functions[markUpdateAsSeen(us-central1)] Successful update operation.

# Deploy Firestore security rules
cd ..
firebase deploy --only firestore:rules

# Expected output:
# ✔ firestore: rules file firestore.rules compiled successfully
```

**Verify deployment:**
1. Open [Firebase Console](https://console.firebase.google.com)
2. Go to **Functions** → Verify 3 new functions appear:
   - `notifyCourseUpdate`
   - `notifyModuleUpdate`
   - `markUpdateAsSeen`
3. Go to **Firestore** → **Rules** → Verify `contentUpdates` rules exist

---

### STEP 2: Test Backend (After Deployment)

```bash
# Method 1: Update a test course in admin app
# 1. Go to admin app
# 2. Edit any course (change title or description)
# 3. Check Firestore Console → contentUpdates collection
# 4. Verify document was created

# Method 2: Check function logs
# Go to Firebase Console → Functions → Logs
# Look for: "Course abc123 update detected: ..."
```

**Expected results:**
- ✅ Update document created in `contentUpdates`
- ✅ Notification document created in `notifications`
- ✅ Enrolled students receive push notification (if critical/important)
- ✅ Function logs show success messages

---

### STEP 3: Deploy Student App (Flutter)

```bash
# Navigate to project root
cd /Users/rojinroy/Projects/briffiniApp/briffiniApp

# Clean build
flutter clean
flutter pub get

# Build for Android (DEBUG for testing)
flutter build apk --debug

# Expected output:
# ✓ Built build/app/outputs/flutter-apk/app-debug.apk

# OR build for release
flutter build apk --release

# Expected output:
# ✓ Built build/app/outputs/flutter-apk/app-release.apk
```

**Install and test:**
```bash
# Install on connected device
flutter install

# OR manually install APK
adb install build/app/outputs/flutter-apk/app-debug.apk
```

---

### STEP 4: Test Student App (After Install)

**1. Test Token Registration:**
```
- Open app
- Login with test user
- Check logs for:
  "✅ FCM token saved successfully to user_tokens collection (flat structure)"
  "Subscribed to topic: student_chat"
  "Subscribed to topic: community_chat"
  "Subscribed to topic: past_questions"
  "Subscribed to topic: notifications"
```

**2. Verify Token in Firestore:**
- Open Firebase Console → Firestore
- Navigate to `user_tokens` collection (top level!)
- Find your token document
- Verify structure:
  ```json
  {
    "token": "dXXXX...",
    "userId": "your_user_id",
    "platform": "android",
    "appType": "student",
    "isActive": true,
    "timestamp": "2025-11-05...",
    "lastUpdated": "2025-11-05..."
  }
  ```

**3. Test Notifications:**

**Test 1: Broadcast Message**
- Admin sends broadcast message
- Student should receive notification
- ✅ PASS: Notification received

**Test 2: Direct Message**
- Admin sends direct message to test user
- Student should receive notification
- ✅ PASS: Notification received

**Test 3: Community Chat**
- Post message in community chat
- All students should receive notification
- ✅ PASS: Notification received

**Test 4: Past Questions**
- Post past question
- All students should receive notification
- ✅ PASS: Notification received

**Test 5: Content Update**
- Admin updates a course (title, new module, etc.)
- Enrolled students receive notification
- ✅ PASS: Notification received
- ✅ PASS: Update indicator shows in course list

---

## 🎯 Complete Testing Checklist

### Backend Tests
- [ ] Cloud functions deployed successfully
- [ ] Firestore rules deployed successfully
- [ ] `notifyCourseUpdate` function triggers on course update
- [ ] `notifyModuleUpdate` function triggers on module update
- [ ] Update documents created in `contentUpdates` collection
- [ ] Notification documents created in `notifications` collection
- [ ] FCM push notifications sent for critical/important updates
- [ ] Function logs show success messages
- [ ] No errors in function logs

### Student App Tests
- [ ] App builds successfully
- [ ] App installs on device
- [ ] User can login
- [ ] FCM token registered to `user_tokens` (flat collection)
- [ ] Token document has all required fields (userId, appType, etc.)
- [ ] All 6 topics subscribed (check logs)
- [ ] Broadcast notifications received
- [ ] Direct notifications received
- [ ] Community chat notifications received
- [ ] Past questions notifications received
- [ ] Content update notifications received
- [ ] Notification navigation works correctly
- [ ] Update indicators show in course list
- [ ] Update indicators disappear after viewing course

---

## 🐛 Common Issues & Solutions

### Issue 1: Functions Not Deploying
**Error:** `Permission denied` or `Deployment failed`

**Solution:**
```bash
# Re-authenticate
firebase login

# Select correct project
firebase use briffini-academy  # Replace with your project ID

# Try deploy again
firebase deploy --only functions
```

---

### Issue 2: Token Not Appearing in Firestore
**Error:** Token shows in old location or not at all

**Solution:**
```bash
# Uninstall app completely
adb uninstall com.yourapp.package  # Replace with your package name

# Reinstall
flutter install

# Login again
# Check Firestore Console → user_tokens collection
```

---

### Issue 3: Notifications Not Received
**Check:**
1. Token in `user_tokens` collection? ✓
2. Token has `appType: 'student'`? ✓
3. Topics subscribed? (Check logs) ✓
4. Notification permissions granted? ✓
5. Device connected to internet? ✓

**Debug:**
```bash
# Check function logs
firebase functions:log

# Look for:
# - "Found X tokens for user..."
# - "Push notifications sent to X tokens"
# - Any error messages
```

---

### Issue 4: Content Updates Not Triggering
**Check:**
1. Functions deployed? ✓
2. Course actually changed? ✓
3. User enrolled in course? (Check `enrolledCourses` array) ✓
4. Function logs show trigger? ✓

**Debug:**
- Firebase Console → Functions → Logs
- Look for: "Course {id} update detected: ..."
- If not appearing, function might not be triggering

---

## 📊 Monitoring After Deployment

### Daily Checks (First Week)
1. **Function Execution:**
   - Firebase Console → Functions → Usage
   - Verify functions are executing
   - Check for errors/timeouts

2. **Notification Delivery:**
   - Firebase Console → Cloud Messaging
   - Check message delivery rates
   - Monitor failed deliveries

3. **User Feedback:**
   - Ask test users if notifications working
   - Check for complaints/issues
   - Monitor app reviews

### Weekly Checks (Ongoing)
1. **Token Cleanup:**
   - Check `cleanupInvalidTokens` function logs
   - Verify invalid tokens being removed
   - Monitor token count growth

2. **Update System:**
   - Check `contentUpdates` collection size
   - Monitor `seenBy` arrays being updated
   - Verify old updates being cleaned up (if cleanup implemented)

---

## 🎉 Success Criteria

### ✅ Deployment Successful When:
1. All functions show "Successful update operation"
2. Firestore rules deployed without errors
3. Student app builds and installs
4. Token appears in flat `user_tokens` collection
5. All 6 topics subscribed (visible in logs)
6. Test notifications received on device
7. Content update notifications trigger correctly
8. Update indicators show and clear properly
9. No errors in function logs
10. No errors in app logs

---

## 📞 Rollback Instructions (If Needed)

### Rollback Cloud Functions:
```bash
# List previous deployments
firebase functions:list

# Rollback to previous version (if available)
# Note: Firebase doesn't have built-in rollback, you'd need to:
# 1. Revert code changes in git
# 2. Redeploy functions

git checkout <previous-commit>
firebase deploy --only functions
```

### Rollback Student App:
```bash
# Reinstall previous APK version
adb install path/to/previous-version.apk
```

---

## 📚 Documentation to Share

### With Student App Team:
1. ✅ `NOTIFICATION_FIX_COMPLETE.md` - Notification fixes documentation
2. ✅ `CONTENT_UPDATE_SYSTEM_COMPLETE.md` - Content update system docs
3. ✅ This file (`DEPLOYMENT_INSTRUCTIONS.md`)

### With Admin Team:
1. ✅ `CONTENT_UPDATE_SYSTEM_COMPLETE.md` - How content updates work
2. ✅ Cloud function logs location
3. ✅ Monitoring instructions

---

## 🚀 Ready to Deploy!

**Pre-deployment Checklist:**
- [x] Code changes committed to git
- [x] Cloud functions tested locally (if possible)
- [x] Student app builds without errors
- [x] Backup of previous APK version
- [x] Test devices ready
- [x] Admin team notified
- [x] Student app team notified
- [x] Documentation prepared

**Deployment Order:**
1. 🏗️ **Backend first** (functions + rules)
2. ✅ **Test backend** (update a course, check Firestore)
3. 📱 **Deploy student app**
4. ✅ **Test student app** (all notification types)
5. 📊 **Monitor** (24-48 hours)
6. 🎉 **Success!**

---

**Good luck with the deployment!** 🚀

If you encounter any issues, check the troubleshooting section above or refer to the Firebase Console logs for detailed error messages.

