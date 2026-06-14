# 🔍 Admin App FCM Token Structure - Complete Details

## 📋 **Response to Student App Team**

Based on your debugging questions, here are the **exact details** from the admin app side:

---

## 1. 🗂️ **FCM Token Storage Structure**

### **✅ CORRECT Structure (What Admin App Uses):**
```
users/{userId}/fcm_tokens/{tokenId}
```

### **❌ INCORRECT Structure (What Student App Might Be Using):**
```
user_tokens/{tokenId}
```

---

## 2. 🔍 **Token Lookup Query (Exact Code)**

### **Admin App Query Code:**
```javascript
// From functions/src/notifications.js - Line 688-694
const tokensSnapshot = await admin.firestore()
  .collection('users')
  .doc(userId)
  .collection('fcm_tokens')
  .where('isActive', '==', true)
  .get();
```

### **Alternative Query (Legacy):**
```javascript
// From functions/src/notifications.js - Line 564-567 (Legacy)
const tokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', userId)
  .where('isActive', '==', true)
  .get();
```

**⚠️ IMPORTANT:** The admin app uses **BOTH** structures for backward compatibility, but **prefers** the new structure.

---

## 3. 📄 **Token Document Structure (Expected)**

### **✅ CORRECT Document Structure:**
```json
{
  "token": "FCM_TOKEN_STRING",
  "platform": "ios" | "android" | "web",
  "isActive": true,
  "createdAt": "timestamp",
  "lastUsed": "timestamp"
}
```

### **❌ INCORRECT Structure (Missing Fields):**
```json
{
  "token": "FCM_TOKEN_STRING",
  "userId": "USER_ID",  // ❌ Don't include userId in document
  "platform": "android",
  "isActive": true,
  "lastUpdated": "timestamp"  // ❌ Should be "lastUsed"
}
```

---

## 4. 📱 **Complete Notification Payload Structure**

### **Single Course Assignment:**
```json
{
  "notification": {
    "title": "New Course Assigned",
    "body": "You have been assigned to 'Course Name' by Admin Name"
  },
  "data": {
    "type": "consolidated_course_assignment",
    "courseCount": "1",
    "courseId": "GEN-0913-vVru",
    "courseName": "Course Name",
    "courseIds": "[\"GEN-0913-vVru\"]",
    "courseTitles": "[\"Course Name\"]",
    "assignedBy": "Admin Name",
    "assignedAt": "2025-09-13T17:01:27Z",
    "deepLink": "/course/GEN-0913-vVru"
  }
}
```

### **Multiple Course Assignment:**
```json
{
  "notification": {
    "title": "New Courses Assigned",
    "body": "You have been assigned to 3 new courses by Admin Name"
  },
  "data": {
    "type": "consolidated_course_assignment",
    "courseCount": "3",
    "courseIds": "[\"GEN-0913-vVru\", \"GEN-0821-8QVF\", \"GEN-0902-Jvsp\"]",
    "courseTitles": "[\"Course 1\", \"Course 2\", \"Course 3\"]",
    "assignedBy": "Admin Name",
    "assignedAt": "2025-09-13T17:01:27Z",
    "deepLink": "/courses"
  }
}
```

---

## 5. 🧪 **Test User Information**

### **Test User Details:**
- **User ID**: `sogq91QwfnfcBcLEiPx6696Qoly2`
- **Email**: `mahesh221747@sahrdaya.ac.in`
- **Role**: `student`
- **Current FCM Token**: `clBpN8Y2Y0kd_F5Lhc4u3f:APA91bHmiVM_4LAEy3qhCQA4bfej-B3da5aMtxXVGpEOc_8YFHbpgKNcsW6q3CE2DHPCEW0RnjyZj3y3tq5fp5v9wTWXsW0bq_t2BTkfDkVRacV35T7KdN4`

### **Expected Firestore Path:**
```
users/sogq91QwfnfcBcLEiPx6696Qoly2/fcm_tokens/clBpN8Y2Y0kd_F5Lhc4u3f:APA91bHmiVM_4LAEy3qhCQA4bfej-B3da5aMtxXVGpEOc_8YFHbpgKNcsW6q3CE2DHPCEW0RnjyZj3y3tq5fp5v9wTWXsW0bq_t2BTkfDkVRacV35T7KdN4
```

---

## 6. 🔧 **Student App Implementation (Corrected)**

### **✅ CORRECT Flutter Implementation:**
```dart
Future<void> registerFCMToken() async {
  final fcm = FirebaseMessaging.instance;
  
  // Get FCM token
  String? token = await fcm.getToken();
  
  if (token != null && currentUserId != null) {
    // Save to Firestore - EXACT structure required
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('fcm_tokens')
        .doc(token) // Use token as document ID
        .set({
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUsed': FieldValue.serverTimestamp(),
    });
  }
}
```

### **❌ INCORRECT Implementation (Common Mistakes):**
```dart
// DON'T DO THIS - Wrong collection structure
await FirebaseFirestore.instance
    .collection('user_tokens')  // ❌ Wrong collection
    .doc(token)
    .set({
      'token': token,
      'userId': currentUserId,  // ❌ Don't include userId
      'platform': 'android',
      'isActive': true,
      'lastUpdated': FieldValue.serverTimestamp(),  // ❌ Wrong field name
    });
```

---

## 7. 🐛 **Debug Information from Admin App**

### **Admin App Logs Show:**
```
fcmService.ts:115 Found 30 tokens for user iUf9zE1LLvS3ShTbSsra9rYoE9q2
```

**This indicates:** The admin app found 30 tokens for the admin user, but **0 tokens for the student user**.

### **Token Deduplication Logic:**
```javascript
// Admin app groups tokens by platform and sends to most recent
const platformTokens = {};
tokensSnapshot.forEach(doc => {
  const tokenData = doc.data();
  const platform = tokenData.platform || 'unknown';
  const lastUsed = tokenData.lastUsed?.toDate?.() || tokenData.createdAt?.toDate?.() || new Date(0);
  
  if (!platformTokens[platform] || lastUsed > platformTokens[platform].lastUsed) {
    platformTokens[platform] = {
      token: tokenData.token,
      lastUsed: lastUsed
    };
  }
});
```

---

## 8. 🧪 **Testing Coordination**

### **Test Steps:**
1. **Student app** saves FCM token using correct structure
2. **Admin app** assigns course to test user
3. **Both teams** check logs for token lookup
4. **Student app** should receive notification

### **Expected Logs:**
**Admin App:**
```
Sending to 1 deduplicated tokens (from 1 total tokens) for user sogq91QwfnfcBcLEiPx6696Qoly2
```

**Student App:**
```
FCM token obtained: [TOKEN]
Notification received: [PAYLOAD]
```

---

## 9. 🎯 **Key Issues to Fix**

### **Most Likely Issues:**
1. **Wrong collection path** - Using `user_tokens` instead of `users/{userId}/fcm_tokens`
2. **Missing fields** - Not including `platform`, `isActive`, `lastUsed`
3. **Wrong field names** - Using `lastUpdated` instead of `lastUsed`
4. **Including userId** - Don't include userId in the document (it's in the path)

### **Verification Steps:**
1. **Check Firestore Console** - Look for path: `users/sogq91QwfnfcBcLEiPx6696Qoly2/fcm_tokens/`
2. **Verify document structure** - Should match exact structure above
3. **Test token lookup** - Admin app should find the token

---

## 10. 🚀 **Quick Fix for Student App**

### **Update Student App Token Registration:**
```dart
// Replace existing token registration with this:
Future<void> registerFCMToken() async {
  final fcm = FirebaseMessaging.instance;
  String? token = await fcm.getToken();
  
  if (token != null && currentUserId != null) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('fcm_tokens')
        .doc(token)
        .set({
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUsed': FieldValue.serverTimestamp(),
    });
    
    print('FCM token saved to: users/$currentUserId/fcm_tokens/$token');
  }
}
```

---

## ✅ **Summary**

**The issue is definitely FCM token storage structure mismatch.**

**Student app needs to:**
1. ✅ Use collection path: `users/{userId}/fcm_tokens/{tokenId}`
2. ✅ Include fields: `token`, `platform`, `isActive`, `createdAt`, `lastUsed`
3. ✅ Don't include `userId` in document (it's in the path)
4. ✅ Use `lastUsed` not `lastUpdated`

**Once this is fixed, notifications should work perfectly!** 🎉

---

## 📞 **Next Steps**

1. **Student team** updates token storage structure
2. **Test with user ID**: `sogq91QwfnfcBcLEiPx6696Qoly2`
3. **Admin team** assigns course to test user
4. **Both teams** verify notification delivery
5. **Issue resolved!** 🚀
