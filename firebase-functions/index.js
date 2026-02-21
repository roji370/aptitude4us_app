const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * NOTE: This file contains functions deployed from the student app repo.
 * DO NOT deploy the admin app's functions from this repo — the admin app
 * maintains its own /functions directory which is the source of truth for:
 *   - sendChatNotification, sendPushNotification, sendCourseAssignmentNotification
 *   - checkExpiringSubscriptions, markExpiredSubscriptions
 *   - violations (checkViolationResetStatus, recordScreenshotViolation, etc.)
 *   - toggleDeviceRestriction, resetUserDevice, getDeviceRestrictionStatus
 *   - setCustomClaims, createUser, deleteUser
 *
 * Functions in THIS file:
 *   - validateUserDevice         (student-specific: exact device ID match)
 *   - registerUserDevice         (student-specific)
 *   - cleanupInvalidTokens       (token hygiene)
 *   - notifyCourseUpdate         (content update tracking)
 *   - notifyModuleUpdate         (content update tracking)
 *   - notifyContentUpdate        (content-type level update tracking)
 *   - notifyContentItemUpdate    (item-level update tracking)
 *   - markUpdateAsSeen           (mark update read)
 *   - getUnseenUpdatesCount      (badge count helper)
 */

// ============================================================================
// DEVICE RESTRICTION — Student-specific (kept as-is, do not change)
// ============================================================================

/**
 * Validate user's device for device restriction.
 * Student app version uses exact device ID matching.
 */
exports.validateUserDevice = onCall(async (request) => {
  const context = {auth: request.auth};
  const data = request.data;
  try {
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

    if (context.auth.uid !== userId) {
      throw new HttpsError(
        "permission-denied",
        "User can only validate their own device",
      );
    }

    console.log(`Validating device for user ${userId}, device: ${currentDeviceId}`);

    const userDoc = await admin.firestore()
      .collection("users")
      .doc(userId)
      .get();

    if (!userDoc.exists) {
      return {
        restrictionEnabled: false,
        isValid: true,
        requiresRegistration: false,
      };
    }

    const userData = userDoc.data();
    const deviceRestriction = userData.deviceRestriction || {};
    let deviceRestrictionEnabled;

    if (deviceRestriction.enabled === undefined) {
      deviceRestrictionEnabled = true;
      console.log(`Device restriction enabled by default for new user ${userId}`);
    } else {
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

    const registeredDeviceId = deviceRestriction.registeredDeviceId;

    if (!registeredDeviceId) {
      console.log(`No device registered for user ${userId}, requiring registration`);
      return {
        restrictionEnabled: true,
        isValid: true,
        requiresRegistration: true,
      };
    }

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
    if (error.code) {
      throw error;
    }
    throw new Error("Failed to validate device: " + error.message);
  }
});

/**
 * Register user device for device restriction.
 */
exports.registerUserDevice = onCall(async (request) => {
  const context = {auth: request.auth, rawRequest: request.rawRequest};
  const data = request.data;
  try {
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

    if (context.auth.uid !== userId) {
      throw new HttpsError(
        "permission-denied",
        "User can only register their own device",
      );
    }

    console.log(`Registering device for user ${userId}: ${deviceId}`);

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
    if (error.code) {
      throw error;
    }
    throw new Error("Failed to register device: " + error.message);
  }
});

// ============================================================================
// TOKEN CLEANUP
// ============================================================================

/**
 * Clean up invalid FCM tokens. Runs daily.
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

    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      const tokenValues = batch.map((t) => t.token);

      try {
        const response = await admin.messaging().sendMulticast({
          data: {test: "true"},
          tokens: tokenValues,
        });

        if (response.failureCount > 0) {
          const failedTokens = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              failedTokens.push(batch[idx].token);
            }
          });

          const deletePromises = failedTokens.map(async (token) => {
            const tokenData = batch.find((t) => t.token === token)?.data;
            const userId = tokenData?.userId;

            await admin.firestore()
              .collection("user_tokens")
              .doc(token)
              .delete();

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
        console.error(`Error checking token batch ${i}-${i + 500}:`, error);
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
 * Helper: returns the emoji icon for a content type.
 * @param {string} contentType - e.g. "pdfs", "videos"
 * @return {string} emoji icon
 */
function getContentIcon(contentType) {
  const icons = {
    videos: "🎥",
    notes: "📝",
    pdfs: "📄",
    images: "🖼️",
    ppts: "📊",
    links: "🔗",
  };
  return icons[contentType] || "📦";
}

/**
 * Helper: send FCM push notifications to a list of student users.
 * @param {Array<string>} userIds - list of user IDs to notify
 * @param {string} title - notification title
 * @param {string} body - notification body
 * @param {Object} data - extra FCM data payload
 * @return {Promise<void>}
 */
async function sendFcmToUsers(userIds, title, body, data = {}) {
  const tokens = [];

  for (const userId of userIds) {
    const tokensSnapshot = await admin.firestore()
      .collection("user_tokens")
      .where("userId", "==", userId)
      .where("appType", "==", "student")
      .where("isActive", "==", true)
      .get();

    tokensSnapshot.docs.forEach((doc) => {
      const token = doc.data().token || doc.id;
      if (token) tokens.push(token);
    });
  }

  if (tokens.length === 0) return;

  try {
    const message = {
      notification: {title, body},
      data: {...data, click_action: "FLUTTER_NOTIFICATION_CLICK"},
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`📱 FCM: ${response.successCount}/${tokens.length} sent`);
  } catch (error) {
    console.error("Error sending FCM notifications:", error);
  }
}

/**
 * 📚 Detect course updates and notify enrolled students.
 * Triggers when a course document is written.
 * IMPORTANT: uses assignedCourseIds (not enrolledCourses).
 */
exports.notifyCourseUpdate = onDocumentWritten("courses/{courseId}", async (event) => {
  const courseId = event.params.courseId;
  const beforeData = event.data.before?.data();
  const afterData = event.data.after?.data();

  if (!afterData) {
    console.log(`Course ${courseId} deleted — skipping notification`);
    return null;
  }
  if (!beforeData) {
    console.log(`Course ${courseId} created — skipping notification`);
    return null;
  }

  try {
    let updateType = "course_general";
    let updateMessage = "Course has been updated";
    let icon = "📚";
    let sendNotification = false;

    if (beforeData.published && !afterData.published) {
      updateType = "course_unpublished";
      updateMessage = "⚠️ Course is no longer available";
      icon = "🔴";
      sendNotification = true;
    } else if (beforeData.deleted !== afterData.deleted && afterData.deleted) {
      updateType = "course_deleted";
      updateMessage = "⚠️ Course has been removed";
      icon = "🔴";
      sendNotification = true;
    } else if (beforeData.title !== afterData.title) {
      updateType = "course_title";
      updateMessage = `Course renamed to "${afterData.title}"`;
      icon = "📚";
      sendNotification = true;
    } else if (beforeData.description !== afterData.description) {
      updateType = "course_description";
      updateMessage = "Course description updated";
      icon = "📝";
      sendNotification = true;
    } else if (beforeData.thumbnail !== afterData.thumbnail) {
      updateType = "course_thumbnail";
      updateMessage = "Course image updated";
      icon = "🖼️";
      sendNotification = false;
    } else if (beforeData.category !== afterData.category) {
      updateType = "course_category";
      updateMessage = `Moved to ${afterData.category} category`;
      icon = "📁";
      sendNotification = false;
    } else {
      updateType = "course_modules_updated";
      updateMessage = "Course modules have been updated";
      icon = "🔄";
      sendNotification = true;
    }

    console.log(`Course ${courseId} updated: ${updateType}`);

    // IMPORTANT: field is assignedCourseIds (not enrolledCourses)
    const usersSnapshot = await admin.firestore()
      .collection("users")
      .where("assignedCourseIds", "array-contains", courseId)
      .get();

    if (usersSnapshot.empty) {
      console.log(`No assigned users for course ${courseId}`);
      return null;
    }

    const assignedUserIds = usersSnapshot.docs.map((doc) => doc.id);
    console.log(`Found ${assignedUserIds.length} assigned users for course ${courseId}`);

    const updateRecord = {
      courseId,
      type: updateType,
      message: updateMessage,
      icon,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      notifiedUsers: assignedUserIds,
      seenBy: [],
      courseName: afterData.title,
      courseThumb: afterData.thumbnail || "",
    };

    const updateRef = await admin.firestore()
      .collection("contentUpdates")
      .add(updateRecord);

    console.log(`Created update record: ${updateRef.id}`);

    if (sendNotification) {
      await admin.firestore().collection("notifications").add({
        title: `${icon} Course Update`,
        body: updateMessage,
        type: "content_update",
        targetApp: "student",
        sender: "system",
        recipients: assignedUserIds,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        link: `/course/${courseId}`,
        metadata: {updateType, courseId, courseName: afterData.title, updateId: updateRef.id, icon},
      });

      await sendFcmToUsers(
        assignedUserIds,
        `${icon} Course Update`,
        updateMessage,
        {type: "content_update", courseId, updateType, updateId: updateRef.id},
      );
    }

    return null;
  } catch (error) {
    console.error("Error in notifyCourseUpdate:", error);
    return null;
  }
});

/**
 * 📖 Detect module updates and notify enrolled students.
 * Triggers when a module document is written.
 */
exports.notifyModuleUpdate = onDocumentWritten("modules/{moduleId}", async (event) => {
  const moduleId = event.params.moduleId;
  const beforeData = event.data.before?.data();
  const afterData = event.data.after?.data();

  if (!afterData) {
    console.log(`Module ${moduleId} deleted — skipping`);
    return null;
  }
  if (!beforeData) {
    console.log(`Module ${moduleId} created — skipping`);
    return null;
  }

  const courseId = afterData.courseId;
  if (!courseId) {
    console.log(`Module ${moduleId} has no courseId — skipping`);
    return null;
  }

  try {
    let updateType = "module_general";
    let updateMessage = "Module has been updated";
    let icon = "📝";

    if (beforeData.title !== afterData.title) {
      updateType = "module_title";
      updateMessage = `Module renamed to "${afterData.title}"`;
      icon = "📝";
    } else if (beforeData.description !== afterData.description) {
      updateType = "module_description";
      updateMessage = `Module "${afterData.title}" description updated`;
      icon = "📝";
    } else if (JSON.stringify(beforeData.content) !== JSON.stringify(afterData.content)) {
      updateType = "module_content";
      const bc = beforeData.content || {};
      const ac = afterData.content || {};

      if ((ac.videos?.length || 0) > (bc.videos?.length || 0)) {
        const count = (ac.videos?.length || 0) - (bc.videos?.length || 0);
        updateMessage = `🎥 ${count} new video${count > 1 ? "s" : ""} added to "${afterData.title}"`;
        icon = "🎥";
      } else if ((ac.pdfs?.length || 0) > (bc.pdfs?.length || 0)) {
        const count = (ac.pdfs?.length || 0) - (bc.pdfs?.length || 0);
        updateMessage = `📄 ${count} new PDF${count > 1 ? "s" : ""} added to "${afterData.title}"`;
        icon = "📄";
      } else if ((ac.notes?.length || 0) > (bc.notes?.length || 0)) {
        const count = (ac.notes?.length || 0) - (bc.notes?.length || 0);
        updateMessage = `📝 ${count} new note${count > 1 ? "s" : ""} added to "${afterData.title}"`;
        icon = "📝";
      } else if ((ac.images?.length || 0) > (bc.images?.length || 0)) {
        const count = (ac.images?.length || 0) - (bc.images?.length || 0);
        updateMessage = `🖼️ ${count} new image${count > 1 ? "s" : ""} added to "${afterData.title}"`;
        icon = "🖼️";
      } else if ((ac.ppts?.length || 0) > (bc.ppts?.length || 0)) {
        const count = (ac.ppts?.length || 0) - (bc.ppts?.length || 0);
        updateMessage = `📊 ${count} new presentation${count > 1 ? "s" : ""} added to "${afterData.title}"`;
        icon = "📊";
      } else if ((ac.links?.length || 0) > (bc.links?.length || 0)) {
        const count = (ac.links?.length || 0) - (bc.links?.length || 0);
        updateMessage = `🔗 ${count} new link${count > 1 ? "s" : ""} added to "${afterData.title}"`;
        icon = "🔗";
      } else {
        updateMessage = `Content updated in "${afterData.title}"`;
        icon = "🔄";
      }
    } else {
      console.log(`Module ${moduleId} updated but no significant changes detected`);
      return null;
    }

    console.log(`Module ${moduleId} in course ${courseId} updated: ${updateType}`);

    const courseDoc = await admin.firestore().collection("courses").doc(courseId).get();
    if (!courseDoc.exists) {
      console.log(`Course ${courseId} not found`);
      return null;
    }
    const courseData = courseDoc.data();

    const usersSnapshot = await admin.firestore()
      .collection("users")
      .where("assignedCourseIds", "array-contains", courseId)
      .get();

    if (usersSnapshot.empty) {
      console.log(`No assigned users for course ${courseId}`);
      return null;
    }

    const assignedUserIds = usersSnapshot.docs.map((doc) => doc.id);

    const updateRef = await admin.firestore().collection("contentUpdates").add({
      courseId,
      moduleId,
      type: updateType,
      message: updateMessage,
      icon,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      notifiedUsers: assignedUserIds,
      seenBy: [],
      moduleName: afterData.title,
      courseName: courseData.title,
    });

    await admin.firestore().collection("notifications").add({
      title: `${icon} Module Update`,
      body: `${courseData.title}: ${updateMessage}`,
      type: "content_update",
      targetApp: "student",
      sender: "system",
      recipients: assignedUserIds,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      link: `/course/${courseId}/module/${moduleId}`,
      metadata: {
        updateType, courseId, moduleId,
        courseName: courseData.title, moduleName: afterData.title,
        updateId: updateRef.id, icon,
      },
    });

    await sendFcmToUsers(
      assignedUserIds,
      `${icon} Module Update`,
      `${courseData.title}: ${updateMessage}`,
      {type: "content_update", courseId, moduleId, updateType, updateId: updateRef.id},
    );

    return null;
  } catch (error) {
    console.error("Error in notifyModuleUpdate:", error);
    return null;
  }
});

/**
 * 📄 Detect content-type changes within modules (PDFs added, videos removed, etc.)
 * Triggers when a module document is written.
 * Stores itemIds in each update doc so the student app can track per-item seen status.
 */
exports.notifyContentUpdate = onDocumentWritten("modules/{moduleId}", async (event) => {
  const moduleId = event.params.moduleId;
  const beforeData = event.data.before?.data();
  const afterData = event.data.after?.data();

  if (!afterData || !beforeData) return null;

  const courseId = afterData.courseId;
  if (!courseId) {
    console.log(`Module ${moduleId} has no courseId — skipping`);
    return null;
  }

  try {
    const beforeContent = beforeData.content || {};
    const afterContent = afterData.content || {};
    const contentTypes = ["videos", "notes", "pdfs", "images", "ppts", "links"];
    const updates = [];

    for (const contentType of contentTypes) {
      const beforeItems = beforeContent[contentType] || [];
      const afterItems = afterContent[contentType] || [];

      // Use stable item key: prefer explicit id, fall back to url/content
      const itemKey = (item) => item.id || item.url || item.content || "";
      const beforeIds = new Set(beforeItems.map(itemKey).filter(Boolean));
      const afterIds = new Set(afterItems.map(itemKey).filter(Boolean));

      const addedIds = [...afterIds].filter((id) => !beforeIds.has(id));
      const removedIds = [...beforeIds].filter((id) => !afterIds.has(id));

      if (addedIds.length > 0) {
        const label = contentType.slice(0, -1);
        updates.push({
          type: `content_${contentType}_updated`,
          message: `${addedIds.length} new ${label}${addedIds.length > 1 ? "s" : ""} added`,
          icon: getContentIcon(contentType),
          contentType,
          changeType: "added",
          count: addedIds.length,
          itemIds: addedIds, // Required for per-item badge tracking in student app
        });
      }

      if (removedIds.length > 0) {
        const label = contentType.slice(0, -1);
        updates.push({
          type: `content_${contentType}_updated`,
          message: `${removedIds.length} ${label}${removedIds.length > 1 ? "s" : ""} removed`,
          icon: getContentIcon(contentType),
          contentType,
          changeType: "removed",
          count: removedIds.length,
          itemIds: removedIds,
        });
      }
    }

    if (updates.length === 0) return null;

    console.log(`Content-level updates in module ${moduleId}: ${updates.length} changes`);

    const courseDoc = await admin.firestore().collection("courses").doc(courseId).get();
    if (!courseDoc.exists) {
      console.log(`Course ${courseId} not found`);
      return null;
    }
    const courseData = courseDoc.data();

    const usersSnapshot = await admin.firestore()
      .collection("users")
      .where("assignedCourseIds", "array-contains", courseId)
      .get();

    if (usersSnapshot.empty) {
      console.log(`No assigned users for course ${courseId}`);
      return null;
    }

    const assignedUserIds = usersSnapshot.docs.map((doc) => doc.id);

    for (const update of updates) {
      const updateRef = await admin.firestore().collection("contentUpdates").add({
        courseId,
        moduleid: moduleId, // kept as-is for backward compat
        moduleId, // canonical camelCase
        type: update.type,
        contentType: update.contentType,
        changeType: update.changeType,
        count: update.count,
        itemIds: update.itemIds, // top-level for direct access
        contentChanges: [{ // nested for student app per-item tracking
          type: update.contentType,
          change: update.changeType,
          count: update.count,
          itemIds: update.itemIds,
        }],
        message: update.message,
        icon: update.changeType === "added" ? "✨" : "⚠️",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        notifiedUsers: assignedUserIds,
        seenBy: [],
        moduleName: afterData.title || "Unknown Module",
        courseName: courseData.title || "Unknown Course",
      });

      console.log(`Created content update doc: ${updateRef.id} (${update.contentType} ${update.changeType})`);
    }

    // Send a single summarised notification
    const summaryMessage = updates.map((u) =>
      u.changeType === "added" ?
        `${getContentIcon(u.contentType)} ${u.count} new ${u.contentType.slice(0, -1)}${u.count > 1 ? "s" : ""} added` :
        `${getContentIcon(u.contentType)} ${u.count} ${u.contentType.slice(0, -1)}${u.count > 1 ? "s" : ""} removed`,
    ).join(". ");

    await sendFcmToUsers(
      assignedUserIds,
      "✨ Content Update",
      `${courseData.title}: ${summaryMessage}`,
      {type: "content_update", courseId, moduleId},
    );

    return null;
  } catch (error) {
    console.error("Error in notifyContentUpdate:", error);
    return null;
  }
});

/**
 * 🔍 Detect individual content item changes (title, URL, publish status).
 * Triggers when a module document is written.
 * More granular than notifyContentUpdate — tracks per-item field changes.
 */
exports.notifyContentItemUpdate = onDocumentWritten("modules/{moduleId}", async (event) => {
  const moduleId = event.params.moduleId;
  const beforeData = event.data.before?.data();
  const afterData = event.data.after?.data();

  if (!afterData || !beforeData) return null;

  const courseId = afterData.courseId;
  if (!courseId) {
    console.log(`Module ${moduleId} has no courseId — skipping`);
    return null;
  }

  try {
    const beforeContent = beforeData.content || {};
    const afterContent = afterData.content || {};
    const contentTypes = ["videos", "notes", "pdfs", "images", "ppts", "links"];
    const itemUpdates = [];

    for (const contentType of contentTypes) {
      const beforeItems = beforeContent[contentType] || [];
      const afterItems = afterContent[contentType] || [];

      const beforeMap = new Map(beforeItems.map((item) => [item.id, item]));
      const afterMap = new Map(afterItems.map((item) => [item.id, item]));

      for (const [itemId, afterItem] of afterMap.entries()) {
        const beforeItem = beforeMap.get(itemId);
        if (!beforeItem) continue; // new item — handled by notifyContentUpdate

        // Title change — record only, no push
        if (beforeItem.title !== afterItem.title) {
          itemUpdates.push({
            type: "content_item_title_changed",
            message: `"${beforeItem.title}" renamed to "${afterItem.title}"`,
            icon: "✏️",
            contentType,
            itemId,
            itemTitle: afterItem.title,
            changeType: "title_changed",
            oldValue: beforeItem.title,
            newValue: afterItem.title,
            sendNotification: false,
          });
        }

        // Description change — record only, no push
        if (beforeItem.description !== afterItem.description) {
          itemUpdates.push({
            type: "content_item_description_changed",
            message: `Description updated for "${afterItem.title}"`,
            icon: "📝",
            contentType,
            itemId,
            itemTitle: afterItem.title,
            changeType: "description_changed",
            sendNotification: false,
          });
        }

        // URL/content replaced — send push
        if (beforeItem.url !== afterItem.url) {
          itemUpdates.push({
            type: "content_item_replaced",
            message: `"${afterItem.title}" has been updated with new content`,
            icon: "🔄",
            contentType,
            itemId,
            itemTitle: afterItem.title,
            changeType: "url_changed",
            sendNotification: true,
          });
        }

        // Publish status changed
        if (beforeItem.isPublished !== afterItem.isPublished) {
          if (afterItem.isPublished === false) {
            itemUpdates.push({
              type: "content_item_unpublished",
              message: `"${afterItem.title}" is no longer available`,
              icon: "🔴",
              contentType,
              itemId,
              itemTitle: afterItem.title,
              changeType: "unpublished",
              sendNotification: true,
            });
          } else {
            itemUpdates.push({
              type: "content_item_published",
              message: `"${afterItem.title}" is now available`,
              icon: "✅",
              contentType,
              itemId,
              itemTitle: afterItem.title,
              changeType: "published",
              sendNotification: true,
            });
          }
        }
      }
    }

    if (itemUpdates.length === 0) return null;

    console.log(`Content-item updates in module ${moduleId}: ${itemUpdates.length} changes`);

    const courseDoc = await admin.firestore().collection("courses").doc(courseId).get();
    if (!courseDoc.exists) {
      console.log(`Course ${courseId} not found`);
      return null;
    }
    const courseData = courseDoc.data();

    const usersSnapshot = await admin.firestore()
      .collection("users")
      .where("assignedCourseIds", "array-contains", courseId)
      .get();

    if (usersSnapshot.empty) {
      console.log(`No assigned users for course ${courseId}`);
      return null;
    }

    const assignedUserIds = usersSnapshot.docs.map((doc) => doc.id);

    for (const update of itemUpdates) {
      const updateRef = await admin.firestore().collection("contentUpdates").add({
        courseId,
        moduleId,
        contentItemId: update.itemId,
        type: update.type,
        message: update.message,
        icon: update.icon,
        contentType: update.contentType,
        itemTitle: update.itemTitle,
        changeType: update.changeType,
        oldValue: update.oldValue,
        newValue: update.newValue,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        notifiedUsers: assignedUserIds,
        seenBy: [],
        moduleName: afterData.title,
        courseName: courseData.title,
      });

      if (update.sendNotification) {
        await admin.firestore().collection("notifications").add({
          title: `${update.icon} Content Item Update`,
          body: `${courseData.title} - ${afterData.title}: ${update.message}`,
          type: "content_item_update",
          targetApp: "student",
          sender: "system",
          recipients: assignedUserIds,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          link: `/course/${courseId}/module/${moduleId}`,
          metadata: {
            updateType: update.type,
            courseId,
            moduleId,
            contentItemId: update.itemId,
            courseName: courseData.title,
            moduleName: afterData.title,
            itemTitle: update.itemTitle,
            updateId: updateRef.id,
            icon: update.icon,
            contentType: update.contentType,
            changeType: update.changeType,
          },
        });

        await sendFcmToUsers(
          assignedUserIds,
          `${update.icon} Content Item Update`,
          `${courseData.title} - ${afterData.title}: ${update.message}`,
          {type: "content_item_update", courseId, moduleId, changeType: update.changeType},
        );
      }
    }

    return null;
  } catch (error) {
    console.error("Error in notifyContentItemUpdate:", error);
    return null;
  }
});

// ============================================================================
// UPDATE TRACKING HELPERS (called from student app)
// ============================================================================

/**
 * ✅ Mark a content update as seen by the current user.
 */
exports.markUpdateAsSeen = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const {updateId} = request.data;
  const userId = request.auth.uid;

  if (!updateId) {
    throw new HttpsError("invalid-argument", "Update ID is required");
  }

  try {
    const updateRef = admin.firestore().collection("contentUpdates").doc(updateId);
    const updateDoc = await updateRef.get();

    if (!updateDoc.exists) {
      throw new Error("Update not found");
    }

    const updateData = updateDoc.data();
    const notifiedUsers = updateData.notifiedUsers || [];
    if (!notifiedUsers.includes(userId)) {
      throw new HttpsError("permission-denied", "User not authorized to mark this update as seen");
    }

    await updateRef.update({
      seenBy: admin.firestore.FieldValue.arrayUnion(userId),
    });

    console.log(`User ${userId} marked update ${updateId} as seen`);
    return {success: true};
  } catch (error) {
    console.error("Error marking update as seen:", error);
    if (error.code) throw error;
    throw new Error("Failed to mark update as seen");
  }
});

/**
 * 🔢 Get count of unseen content updates for the current user.
 */
exports.getUnseenUpdatesCount = onCall({cors: true}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const userId = request.auth.uid;

  try {
    const updatesSnapshot = await admin.firestore()
      .collection("contentUpdates")
      .where("notifiedUsers", "array-contains", userId)
      .get();

    let unseenCount = 0;
    updatesSnapshot.forEach((doc) => {
      const seenBy = doc.data().seenBy || [];
      if (!seenBy.includes(userId)) {
        unseenCount++;
      }
    });

    return {success: true, unseenCount};
  } catch (error) {
    console.error("Error getting unseen updates count:", error);
    throw new Error("Failed to get unseen updates count");
  }
});
