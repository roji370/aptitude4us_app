import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../utils/logger.dart';

/// Writes the student's IANA timezone to their user doc.
///
/// Called once at login (fire-and-forget). The Firestore security rules
/// allow students to update only `timezone` (among other safe fields)
/// on their own user doc.
///
/// The server uses this timezone for streak date boundaries:
/// a student in `America/New_York` should have their "day" start/end
/// at midnight Eastern, not midnight UTC or IST.
class TimezoneService {
  /// Writes the device's current IANA timezone (e.g. "Asia/Kolkata",
  /// "America/New_York") to `users/{uid}.timezone`.
  ///
  /// Fire-and-forget — errors are logged but never thrown. A missing
  /// timezone just means the server falls back to its default.
  static Future<void> writeTimezoneToUserDoc() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final tz = await FlutterTimezone.getLocalTimezone();
      if (tz.isEmpty) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'timezone': tz});

      Logger.i('TimezoneService: wrote timezone "$tz" for ${user.uid}');
    } catch (e) {
      // Non-fatal — server falls back to default timezone.
      Logger.w('TimezoneService: failed to write timezone: $e');
    }
  }
}

