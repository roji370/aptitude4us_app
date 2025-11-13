const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * NOTE: This file previously contained a function for sending chat notifications.
 * This functionality has been removed as it's now handled by the admin app team's
 * notification system. We maintain only the token cleanup function below.
 *
 * The student app still registers tokens in Firestore collections:
 * - user_tokens/{token}
 * - users/{userId}/tokens/{token}
 *
 * These tokens are used by the admin app's notification system.
 */

/**
 * Cloud Function to validate user device for device restriction
 * Checks if a user's device is allowed to login
 */
exports.validateUserDevice = onCall(async (request) => {
  const context = {auth: request.auth};
  const data = request.data;
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to validate device",
      );
    }

    const {userId, currentDeviceId} = data;

    if (!userId || !currentDeviceId) {
      throw new HttpsError(
        "invalid-argument",
        "userId and currentDeviceId are required",
      );
    }

    // Check if the requesting user matches the userId (security check)
    if (context.auth.uid !== userId) {
      throw new HttpsError(
        "permission-denied",
        "User can only validate their own device",
      );
    }

    console.log(`Validating device for user ${userId}, device: ${currentDeviceId}`);

    // Get user document to check device restriction settings
    const userDoc = await admin.firestore()
      .collection("users")
      .doc(userId)
      .get();

    if (!userDoc.exists) {
      // User doesn't exist, allow login without restriction
      return {
        restrictionEnabled: false,
        isValid: true,
        requiresRegistration: false,
      };
    }

    const userData = userDoc.data();

    // Check if device restriction is enabled for this user
    // Use the admin app's database schema: deviceRestriction.enabled
    const deviceRestriction = userData.deviceRestriction || {};
    let deviceRestrictionEnabled;

    if (deviceRestriction.enabled === undefined) {
      // New user - enable device restriction by default
      deviceRestrictionEnabled = true;
      console.log(`Device restriction enabled by default for new user ${userId}`);
    } else {
      // Existing user - use admin setting from deviceRestriction.enabled
      deviceRestrictionEnabled = deviceRestriction.enabled === true;
      const status = deviceRestrictionEnabled ? "enabled" : "disabled";
      console.log(`Device restriction ${status} by admin for user ${userId}`);
    }

    if (!deviceRestrictionEnabled) {
      return {
        restrictionEnabled: false,
        isValid: true,
        requiresRegistration: false,
      };
    }

    // Device restriction is enabled, check registered device
    const registeredDeviceId = deviceRestriction.registeredDeviceId;

    if (!registeredDeviceId) {
      // No device registered yet, require registration
      console.log(`No device registered for user ${userId}, requiring registration`);
      return {
        restrictionEnabled: true,
        isValid: true,
        requiresRegistration: true,
      };
    }

    // Check if current device matches registered device
    const isValid = registeredDeviceId === currentDeviceId;

    console.log(`Device validation for user ${userId}: ${isValid ? "VALID" : "INVALID"}`);
    console.log(`Registered: ${registeredDeviceId}, Current: ${currentDeviceId}`);

    return {
      restrictionEnabled: true,
      isValid: isValid,
      requiresRegistration: false,
    };
  } catch (error) {
    console.error("Error in validateUserDevice:", error);

    // Re-throw HttpsError as is
    if (error.code) {
      throw error;
    }

    // Wrap other errors
    throw new Error("Failed to validate device: " + error.message);
  }
});

/**
 * Cloud Function to register a user's device for device restriction
 * Stores device information for the user
 */
exports.registerUserDevice = onCall(async (request) => {
  const context = {auth: request.auth, rawRequest: request.rawRequest};
  const data = request.data;
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to register device",
      );
    }

    const {userId, deviceId, deviceInfo} = data;

    if (!userId || !deviceId) {
      throw new HttpsError(
        "invalid-argument",
        "userId and deviceId are required",
      );
    }

    // Check if the requesting user matches the userId (security check)
    if (context.auth.uid !== userId) {
      throw new HttpsError(
        "permission-denied",
        "User can only register their own device",
      );
    }

    console.log(`Registering device for user ${userId}: ${deviceId}`);

    // Update user document with device information (match admin app schema)
    const updateData = {
      "deviceRestriction.registeredDeviceId": deviceId,
      "deviceRestriction.registeredAt": admin.firestore.FieldValue.serverTimestamp(),
      "deviceRestriction.enabled": true,
      "lastDeviceUpdate": admin.firestore.FieldValue.serverTimestamp(),
    };

    if (deviceInfo) {
      updateData.deviceInfo = deviceInfo;
    }

    await admin.firestore()
      .collection("users")
      .doc(userId)
      .update(updateData);

    // Log device registration event
    await admin.firestore()
      .collection("device_logs")
      .add({
        userId: userId,
        deviceId: deviceId,
        deviceInfo: deviceInfo || "Unknown Device",
        action: "register",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        userAgent: context.rawRequest?.headers?.["user-agent"] || "Unknown",
      });

    console.log(`Device registered successfully for user ${userId}`);

    return {
      success: true,
      message: "Device registered successfully",
    };
  } catch (error) {
    console.error("Error in registerUserDevice:", error);

    // Re-throw HttpsError as is
    if (error.code) {
      throw error;
    }

    // Wrap other errors
    throw new Error("Failed to register device: " + error.message);
  }
});

/**
 * Cloud Function to clean up invalid tokens
 * Runs on a schedule (once a day) to remove tokens that are no longer valid
 */
exports.cleanupInvalidTokens = onSchedule("every 24 hours", async (event) => {
  try {
    const tokensSnapshot = await admin.firestore()
      .collection("user_tokens")
      .get();

    if (tokensSnapshot.empty) {
      console.log("No tokens to clean up");
      return null;
    }

    const tokens = tokensSnapshot.docs.map((doc) => ({
      token: doc.id,
      data: doc.data(),
    }));

    // Check tokens in batches of 500 (FCM limit)
    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      const tokenValues = batch.map((t) => t.token);

      try {
        const response = await admin.messaging().sendMulticast({
          data: {test: "true"},
          tokens: tokenValues,
        });

        // Process the failed tokens
        if (response.failureCount > 0) {
          const failedTokens = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              failedTokens.push(batch[idx].token);
            }
          });

          // Delete the invalid tokens
          const deletePromises = failedTokens.map(async (token) => {
            const tokenData = batch.find((t) => t.token === token)?.data;
            const userId = tokenData?.userId;

            // Delete from user_tokens collection
            await admin.firestore()
              .collection("user_tokens")
              .doc(token)
              .delete();

            // If we have a userId, also delete from the user's tokens collection
            if (userId) {
              await admin.firestore()
                .collection("users")
                .doc(userId)
                .collection("tokens")
                .doc(token)
                .delete();
            }
          });

          await Promise.all(deletePromises);
          console.log(`Deleted ${failedTokens.length} invalid tokens`);
        }
      } catch (error) {
        console.error(`Error checking token batch ${i}-${i+500}:`, error);
      }
    }

    return {success: true};
  } catch (error) {
    console.error("Error cleaning up tokens:", error);
    return {error: error.message};
  }
});

// ============================================================================
// CONTENT UPDATE NOTIFICATIONS
// ============================================================================

/**
 * 📚 Detect course updates and notify enrolled students
 * Triggers when a course document is created, updated, or deleted
 */
exports.notifyCourseUpdate = onDocumentWritten("courses/{courseId}", async (event) => {
  const courseId = event.params.courseId;
  const beforeData = event.data.before?.data();
  const afterData = event.data.after?.data();

  // Skip if course is being deleted or newly created
  if (!afterData || !beforeData) {
    console.log(`Course ${courseId} is being ${!afterData ? "deleted" : "created"} - skipping notification`);
    return null;
  }

  try {
    let priority = "medium";
    let updateType = "course_general";
    let updateMessage = "Course has been updated";

    // 🔴 CRITICAL: Course unpublished
    if (beforeData.published && !afterData.published) {
      priority = "critical";
      updateType = "course_unpublished";
      updateMessage = "⚠️ Course is no longer available";
    } else if ((beforeData.modules?.length || 0) > (afterData.modules?.length || 0)) {
      // 🔴 CRITICAL: Module deleted (if modules stored as array in course)
      priority = "critical";
      updateType = "module_deleted";
      const deleted = (beforeData.modules?.length || 0) - (afterData.modules?.length || 0);
      updateMessage = `⚠️ ${deleted} module${deleted > 1 ? "s" : ""} removed from course`;
    } else if ((afterData.modules?.length || 0) > (beforeData.modules?.length || 0)) {
      // 🟠 IMPORTANT: New module added
      priority = "important";
      updateType = "module_added";
      const added = (afterData.modules?.length || 0) - (beforeData.modules?.length || 0);
      updateMessage = `🎉 ${added} new module${added > 1 ? "s" : ""} added`;
    } else if (beforeData.title !== afterData.title) {
      // 🟠 IMPORTANT: Title changed
      priority = "important";
      updateType = "course_title";
      updateMessage = `📚 Course renamed to "${afterData.title}"`;
    } else if (beforeData.description !== afterData.description) {
      // 🟠 IMPORTANT: Description changed
      priority = "important";
      updateType = "course_description";
      updateMessage = "📝 Course description updated";
    } else if (beforeData.thumbnail !== afterData.thumbnail) {
      // 🟡 MEDIUM: Thumbnail changed
      priority = "medium";
      updateType = "course_thumbnail";
      updateMessage = "🖼️ Course image updated";
    } else if (beforeData.category !== afterData.category) {
      // 🟡 MEDIUM: Category changed
      priority = "medium";
      updateType = "course_category";
      updateMessage = `📁 Moved to ${afterData.category || "different"} category`;
    } else if (JSON.stringify(beforeData.modules) !== JSON.stringify(afterData.modules)) {
      // 🟡 MEDIUM: Modules reordered or content changed
      priority = "medium";
      updateType = "modules_updated";
      updateMessage = "🔄 Course content updated";
    } else {
      // No significant change detected
      console.log(`No significant changes detected for course ${courseId}`);
      return null;
    }

    console.log(`Course ${courseId} update detected: ${updateType} (${priority})`);

    // Get all users enrolled in this course
    const usersSnapshot = await admin.firestore()
      .collection("users")
      .where("enrolledCourses", "array-contains", courseId)
      .get();

    if (usersSnapshot.empty) {
      console.log(`No enrolled users for course ${courseId}`);
      return null;
    }

    const enrolledUserIds = usersSnapshot.docs.map((doc) => doc.id);
    console.log(`Found ${enrolledUserIds.length} enrolled users for course ${courseId}`);

    // Create update tracking document
    const updateRecord = {
      courseId,
      type: updateType,
      priority,
      message: updateMessage,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      notifiedUsers: enrolledUserIds,
      seenBy: [], // Track who has seen this update
    };

    const updateRef = await admin.firestore()
      .collection("contentUpdates")
      .add(updateRecord);

    console.log(`Created update record: ${updateRef.id}`);

    // Send notification based on priority (only for critical and important)
    if (priority === "critical" || priority === "important") {
      // Create notification document
      const notificationData = {
        title: priority === "critical" ? "⚠️ Course Update" : "📚 Course Update",
        body: updateMessage,
        type: "content_update",
        targetApp: "student",
        sender: "system",
        recipients: enrolledUserIds,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        link: `/course/${courseId}`,
        metadata: {
          updateType,
          priority,
          courseId,
          courseName: afterData.title,
          updateId: updateRef.id,
        },
      };

      await admin.firestore().collection("notifications").add(notificationData);
      console.log(`✅ Notification sent to ${enrolledUserIds.length} students for ${priority} update`);

      // For critical/important updates, also send FCM push notifications
      const tokens = [];

      // Get FCM tokens for all enrolled users
      for (const userId of enrolledUserIds) {
        const tokensSnapshot = await admin.firestore()
          .collection("user_tokens")
          .where("userId", "==", userId)
          .where("isActive", "==", true)
          .get();

        tokensSnapshot.docs.forEach((doc) => {
          tokens.push(doc.id);
        });
      }

      if (tokens.length > 0) {
        try {
          const message = {
            notification: {
              title: notificationData.title,
              body: updateMessage,
            },
            data: {
              type: "content_update",
              courseId,
              updateType,
              priority,
              updateId: updateRef.id,
            },
          };

          // Send to tokens in batches of 500 (FCM limit)
          for (let i = 0; i < tokens.length; i += 500) {
            const batch = tokens.slice(i, i + 500);
            await admin.messaging().sendMulticast({
              ...message,
              tokens: batch,
            });
          }

          console.log(`📱 Push notifications sent to ${tokens.length} tokens`);
        } catch (error) {
          console.error("Error sending push notifications:", error);
        }
      }
    } else {
      // Medium/low priority - just create the update record for UI indicators
      console.log(`Update record created for ${priority} priority - no push notification sent`);
    }

    return null;
  } catch (error) {
    console.error("Error in notifyCourseUpdate:", error);
    return null;
  }
});

/**
 * 📖 Detect module updates within a course (if using subcollection structure)
 * Triggers when a module document is created, updated, or deleted
 */
exports.notifyModuleUpdate = onDocumentWritten(
  "courses/{courseId}/modules/{moduleId}",
  async (event) => {
    const courseId = event.params.courseId;
    const moduleId = event.params.moduleId;
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();

    // Skip if module is being deleted or newly created
    if (!afterData || !beforeData) {
      console.log(`Module ${moduleId} in course ${courseId} is being ${!afterData ? "deleted" : "created"}`);
      return null;
    }

    try {
      let priority = "medium";
      let updateType = "module_general";
      let updateMessage = "Module has been updated";

      // 🔴 CRITICAL: Content removed
      if ((beforeData.content?.length || 0) > (afterData.content?.length || 0)) {
        priority = "critical";
        updateType = "content_removed";
        const removed = (beforeData.content?.length || 0) - (afterData.content?.length || 0);
        updateMessage = `⚠️ ${removed} item${removed > 1 ? "s" : ""} removed from module`;
      } else if ((afterData.content?.length || 0) > (beforeData.content?.length || 0)) {
        // 🟠 IMPORTANT: New content added
        priority = "important";
        updateType = "content_added";
        const added = (afterData.content?.length || 0) - (beforeData.content?.length || 0);
        updateMessage = `🎉 ${added} new item${added > 1 ? "s" : ""} added to module`;
      } else if (beforeData.title !== afterData.title) {
        // 🟠 IMPORTANT: Module title changed
        priority = "important";
        updateType = "module_title";
        updateMessage = `📖 Module renamed to "${afterData.title}"`;
      } else if (JSON.stringify(beforeData.content) !== JSON.stringify(afterData.content)) {
        // 🟡 MEDIUM: Content reordered or updated
        priority = "medium";
        updateType = "module_content";
        updateMessage = "🔄 Module content updated";
      } else if (beforeData.description !== afterData.description) {
        // 🟡 MEDIUM: Description changed
        priority = "medium";
        updateType = "module_description";
        updateMessage = "📝 Module description updated";
      } else {
        // No significant change
        console.log(`No significant changes detected for module ${moduleId}`);
        return null;
      }

      console.log(`Module ${moduleId} update detected: ${updateType} (${priority})`);

      // Get course info
      const courseDoc = await admin.firestore()
        .collection("courses")
        .doc(courseId)
        .get();

      if (!courseDoc.exists) {
        console.log(`Course ${courseId} not found`);
        return null;
      }

      const courseData = courseDoc.data();

      // Get enrolled users
      const usersSnapshot = await admin.firestore()
        .collection("users")
        .where("enrolledCourses", "array-contains", courseId)
        .get();

      if (usersSnapshot.empty) {
        console.log(`No enrolled users for course ${courseId}`);
        return null;
      }

      const enrolledUserIds = usersSnapshot.docs.map((doc) => doc.id);

      // Create update tracking
      const updateRecord = {
        courseId,
        moduleId,
        type: updateType,
        priority,
        message: updateMessage,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        notifiedUsers: enrolledUserIds,
        seenBy: [],
      };

      const updateRef = await admin.firestore()
        .collection("contentUpdates")
        .add(updateRecord);

      console.log(`Created module update record: ${updateRef.id}`);

      // Send notification for critical/important updates
      if (priority === "critical" || priority === "important") {
        const notificationData = {
          title: priority === "critical" ? "⚠️ Module Update" : "📖 Module Update",
          body: `${courseData.title}: ${updateMessage}`,
          type: "content_update",
          targetApp: "student",
          sender: "system",
          recipients: enrolledUserIds,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          link: `/course/${courseId}/module/${moduleId}`,
          metadata: {
            updateType,
            priority,
            courseId,
            moduleId,
            courseName: courseData.title,
            moduleName: afterData.title,
            updateId: updateRef.id,
          },
        };

        await admin.firestore().collection("notifications").add(notificationData);
        console.log(`✅ Module update notification sent to ${enrolledUserIds.length} students`);

        // Send FCM push notifications for critical/important updates
        const tokens = [];

        for (const userId of enrolledUserIds) {
          const tokensSnapshot = await admin.firestore()
            .collection("user_tokens")
            .where("userId", "==", userId)
            .where("isActive", "==", true)
            .get();

          tokensSnapshot.docs.forEach((doc) => {
            tokens.push(doc.id);
          });
        }

        if (tokens.length > 0) {
          try {
            const message = {
              notification: {
                title: notificationData.title,
                body: notificationData.body,
              },
              data: {
                type: "content_update",
                courseId,
                moduleId,
                updateType,
                priority,
                updateId: updateRef.id,
              },
            };

            for (let i = 0; i < tokens.length; i += 500) {
              const batch = tokens.slice(i, i + 500);
              await admin.messaging().sendMulticast({
                ...message,
                tokens: batch,
              });
            }

            console.log(`📱 Push notifications sent to ${tokens.length} tokens`);
          } catch (error) {
            console.error("Error sending push notifications:", error);
          }
        }
      }

      return null;
    } catch (error) {
      console.error("Error in notifyModuleUpdate:", error);
      return null;
    }
  });

/**
 * 📄 Detect content changes within modules (PDFs, videos, etc.)
 * Triggers when module content array changes
 */
exports.notifyContentUpdate = onDocumentWritten(
  "courses/{courseId}/modules/{moduleId}",
  async (event) => {
    const courseId = event.params.courseId;
    const moduleId = event.params.moduleId;
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();

    // Skip if module is being deleted or newly created
    if (!afterData || !beforeData) {
      return null;
    }

    // Get content arrays
    const beforeContent = beforeData.content || {};
    const afterContent = afterData.content || {};

    // Check each content type (videos, pdfs, notes, etc.)
    const contentTypes = ["videos", "pdfs", "notes", "images", "links"];
    const changes = [];

    for (const type of contentTypes) {
      const beforeItems = beforeContent[type] || [];
      const afterItems = afterContent[type] || [];

      if (beforeItems.length !== afterItems.length) {
        const diff = afterItems.length - beforeItems.length;
        changes.push({
          type,
          change: diff > 0 ? "added" : "deleted",
          count: Math.abs(diff),
        });
      }
    }

    // If no content changes, skip
    if (changes.length === 0) {
      return null;
    }

    try {
      // Get course info
      const courseDoc = await admin.firestore()
        .collection("courses")
        .doc(courseId)
        .get();

      if (!courseDoc.exists) {
        console.log(`Course ${courseId} not found`);
        return null;
      }

      const courseData = courseDoc.data();
      const courseName = courseData.title || "Unknown Course";

      // Get enrolled users
      const usersSnapshot = await admin.firestore()
        .collection("users")
        .where("assignedCourseIds", "array-contains", courseId)
        .get();

      if (usersSnapshot.empty) {
        console.log(`No users enrolled in course ${courseId}`);
        return null;
      }

      const enrolledUserIds = usersSnapshot.docs.map((doc) => doc.id);

      // Create detailed message
      let updateMessage = "";
      let priority = "medium";
      const icons = {
        videos: "🎥",
        pdfs: "📄",
        notes: "📝",
        images: "🖼️",
        links: "🔗",
      };

      for (const change of changes) {
        const icon = icons[change.type] || "📎";
        const typeName = change.type.charAt(0).toUpperCase() + change.type.slice(1);
        if (change.change === "added") {
          updateMessage += `${icon} ${change.count} new ${typeName} added. `;
          priority = "important"; // New content is important
        } else {
          updateMessage += `${icon} ${change.count} ${typeName} removed. `;
          priority = "critical"; // Deleted content is critical
        }
      }

      // Create contentUpdate record
      const updateData = {
        courseId,
        courseName,
        moduleId,
        moduleName: afterData.title || "Unknown Module",
        type: "content_change",
        message: updateMessage.trim(),
        priority,
        icon: changes[0].change === "added" ? "✨" : "⚠️",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        notifiedUsers: enrolledUserIds,
        seenBy: [],
        contentChanges: changes, // Store detailed changes
      };

      await admin.firestore()
        .collection("contentUpdates")
        .add(updateData);

      console.log(`Content update record created for module ${moduleId} in course ${courseId}`);

      // Send push notification for important changes
      if (priority === "critical" || priority === "important") {
        try {
          const tokens = [];
          for (const userId of enrolledUserIds) {
            const userTokensSnapshot = await admin.firestore()
              .collection("user_tokens")
              .where("userId", "==", userId)
              .where("appType", "==", "student")
              .where("isActive", "==", true)
              .get();

            userTokensSnapshot.docs.forEach((doc) => {
              tokens.push(doc.data().token);
            });
          }

          if (tokens.length > 0) {
            const message = {
              notification: {
                title: priority === "critical" ? "⚠️ Content Removed" : "✨ New Content Available",
                body: `${courseName}: ${updateMessage}`,
              },
              data: {
                type: "content_update",
                courseId,
                moduleId,
                priority,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
              tokens,
            };

            const response = await admin.messaging().sendEachForMulticast(message);
            console.log(`Sent ${response.successCount} content update notifications`);
          }
        } catch (error) {
          console.error("Error sending content update notifications:", error);
        }
      }

      return null;
    } catch (error) {
      console.error("Error in notifyContentUpdate:", error);
      return null;
    }
  });

/**
 * ✅ Mark content update as seen by user
 * Called from student app when user views the updated content
 */
exports.markUpdateAsSeen = onCall(async (request) => {
  const context = {auth: request.auth};
  if (!context.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication required",
    );
  }

  const {updateId} = request.data;
  const userId = context.auth.uid;

  if (!updateId) {
    throw new Error("Update ID is required");
  }

  try {
    const updateRef = admin.firestore().collection("contentUpdates").doc(updateId);
    const updateDoc = await updateRef.get();

    if (!updateDoc.exists) {
      throw new Error("Update not found");
    }

    // Verify user is in notifiedUsers list
    const updateData = updateDoc.data();
    if (!updateData.notifiedUsers.includes(userId)) {
      throw new Error("User not authorized to mark this update");
    }

    await updateRef.update({
      seenBy: admin.firestore.FieldValue.arrayUnion(userId),
    });

    console.log(`User ${userId} marked update ${updateId} as seen`);

    return {success: true};
  } catch (error) {
    console.error("Error marking update as seen:", error);

    if (error.code) {
      throw error;
    }

    throw new Error("Failed to mark update as seen");
  }
});
