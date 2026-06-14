# 🔍 Admin App: Add Detailed Notification Logging

## Problem

Admin logs show "notification sent successfully" but iOS devices don't receive notifications. We need more detailed logging to diagnose the issue.

---

## Required: Add Logging to Course Assignment Function

**File:** `functions/src/notifications.js` (or similar)  
**Function:** `sendCourseAssignmentNotification` (around line 563)

### Add These Logs:

```javascript
// After querying tokens (around line 563-567):
const tokensSnapshot = await admin.firestore()
  .collection('user_tokens')
  .where('userId', '==', userId)
  .where('isActive', '==', true)
  .where('appType', '==', 'student')  // ← ADD THIS (from previous fix)
  .get();

// ✅ ADD THIS LOGGING:
console.log(`\n=== Course Assignment Notification Debug ===`);
console.log(`User ID: ${userId}`);
console.log(`Course ID: ${courseId}`);
console.log(`Found ${tokensSnapshot.size} student tokens`);

// Log each token with platform
tokensSnapshot.forEach(doc => {
  const tokenData = doc.data();
  console.log(`  - Platform: ${tokenData.platform}, Token: ${tokenData.token.substring(0, 30)}...`);
});

// After deduplicating by platform (around line 570-585):
const platformTokens = {};
tokensSnapshot.forEach(doc => {
  const tokenData = doc.data();
  const platform = tokenData.platform || 'unknown';
  // ... existing code ...
});

// ✅ ADD THIS LOGGING:
console.log(`\nDeduplicated tokens by platform:`);
Object.keys(platformTokens).forEach(platform => {
  console.log(`  - ${platform}: ${platformTokens[platform].token.substring(0, 30)}...`);
});

// After sending to each token (around line 591-598):
for (const platform of Object.keys(platformTokens)) {
  const tokenData = platformTokens[platform];
  try {
    const response = await admin.messaging().send({
      token: tokenData.token,
      ...payload
    });
    
    // ✅ ADD THIS LOGGING:
    console.log(`\n✅ ${platform} notification sent:`, response);
    
  } catch (error) {
    // ✅ ADD THIS LOGGING:
    console.error(`\n❌ ${platform} notification FAILED:`, {
      error: error.message,
      code: error.code,
      token: tokenData.token.substring(0, 30) + '...'
    });
  }
}

console.log(`\n=== End Debug ===\n`);
```

---

## What This Will Show

After adding logging, when you assign a course, you'll see:

### **Successful iOS delivery:**
```
=== Course Assignment Notification Debug ===
User ID: KFrsPCjr35T7hzCJ5a9JVDZ4nKE2
Course ID: GEN-1105-v3xg
Found 1 student tokens
  - Platform: iOS, Token: ciNkfL01tUVupYfxPbVryg:APA91b...

Deduplicated tokens by platform:
  - iOS: ciNkfL01tUVupYfxPbVryg:APA91b...

✅ iOS notification sent: { messageId: '0:1234567890' }

=== End Debug ===
```

### **Failed iOS delivery:**
```
=== Course Assignment Notification Debug ===
User ID: KFrsPCjr35T7hzCJ5a9JVDZ4nKE2
Course ID: GEN-1105-v3xg
Found 1 student tokens
  - Platform: iOS, Token: ciNkfL01tUVupYfxPbVryg:APA91b...

Deduplicated tokens by platform:
  - iOS: ciNkfL01tUVupYfxPbVryg:APA91b...

❌ iOS notification FAILED: {
  error: 'The registration token is not valid',
  code: 'messaging/invalid-registration-token',
  token: 'ciNkfL01tUVupYfxPbVryg:APA91b...'
}

=== End Debug ===
```

### **No iOS tokens found:**
```
=== Course Assignment Notification Debug ===
User ID: KFrsPCjr35T7hzCJ5a9JVDZ4nKE2
Course ID: GEN-1105-v3xg
Found 0 student tokens  ← PROBLEM!

=== End Debug ===
```

---

## How to Test

1. **Deploy the changes:**
   ```bash
   firebase deploy --only functions
   ```

2. **Assign a course to the iOS student**

3. **Check Firebase Console Logs:**
   - Go to: https://console.firebase.google.com/project/course-c18bb/functions/logs
   - Look for the debug output
   - Share the logs with student app team

---

## What the Logs Will Tell Us

| Log Output | Meaning | Solution |
|------------|---------|----------|
| `Found 0 student tokens` | No tokens in database | Student app not registering tokens |
| `Found X tokens` but no iOS platform | iOS token not saved correctly | Check student app token save code |
| iOS token found + `✅ notification sent` | Delivery successful | iOS should receive notification |
| iOS token found + `❌ FAILED: invalid-registration-token` | Token is invalid/expired | iOS app needs to refresh token |
| iOS token found + `❌ FAILED: apns-token-not-set` | APNs configuration issue | Check Firebase APNs keys |

---

## Priority

**Add this logging IMMEDIATELY** - it will show us exactly what's happening:
1. Are student tokens being queried?
2. Is the iOS token included?
3. Is FCM actually sending to iOS?
4. What errors (if any) are occurring?

---

## Next Steps

1. ✅ Add `appType` filter (from SEND_TO_ADMIN_TEAM.md)
2. ✅ Add detailed logging (this document)
3. ✅ Deploy functions
4. ✅ Test course assignment
5. ✅ Share Firebase Console logs

This will give us the smoking gun to identify exactly why iOS isn't receiving notifications!

