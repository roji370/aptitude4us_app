const functions = require("firebase-functions");
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
exports.validateUserDevice = functions.https.onCall(async (data, context) => {
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to validate device",
      );
    }

    const {userId, currentDeviceId} = data;

    if (!userId || !currentDeviceId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "userId and currentDeviceId are required",
      );
    }

    // Check if the requesting user matches the userId (security check)
    if (context.auth.uid !== userId) {
      throw new functions.https.HttpsError(
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
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    // Wrap other errors
    throw new functions.https.HttpsError(
      "internal",
      "Failed to validate device: " + error.message,
    );
  }
});

/**
 * Cloud Function to register a user's device for device restriction
 * Stores device information for the user
 */
exports.registerUserDevice = functions.https.onCall(async (data, context) => {
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to register device",
      );
    }

    const {userId, deviceId, deviceInfo} = data;

    if (!userId || !deviceId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "userId and deviceId are required",
      );
    }

    // Check if the requesting user matches the userId (security check)
    if (context.auth.uid !== userId) {
      throw new functions.https.HttpsError(
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
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    // Wrap other errors
    throw new functions.https.HttpsError(
      "internal",
      "Failed to register device: " + error.message,
    );
  }
});

/**
 * Cloud Function to clean up invalid tokens
 * Runs on a schedule (once a day) to remove tokens that are no longer valid
 */
exports.cleanupInvalidTokens = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async (context) => {
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
