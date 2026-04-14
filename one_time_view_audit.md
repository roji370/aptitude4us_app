# One-Time View Feature — Complete Production Audit

## Previously Fixed ✅
1. Unstable content IDs (URL → stable moduleId_type_title_order)
2. Content blocked mid-session after 80% mark (split _firestoreWrittenContentIds)
3. Concurrent _checkAndEnforceOneTimeView calls (added _pendingCheckContentIds guard)
4. Content exposed during Firestore check window (checking placeholder)

## Previously Identified Open Issues
- Issue 5 — CRITICAL: userId == null leaks _pendingCheckContentIds
- Issue 6 — CRITICAL: Two-device simultaneous access (no server-side atomic guard)
- Issue 7 — HIGH: Very short video (lt 2s) fires 80% callback at position=0
- Issue 11 — CRITICAL: !mounted early returns leak _pendingCheckContentIds
- Issue 12 — MEDIUM: Dead code _buildOldPortraitLayout still calls _buildContentView

## Fixed ✅
### Issue 13 — CRITICAL: Dialog re-appears after back-navigate (all content types)

**Affected content types (before fix):**
| Type  | Write mechanism              | Bug                                  |
|-------|------------------------------|--------------------------------------|
| video | 80% progress callback        | Back before 80% → re-dialog ❌       |
| pdf   | onRender callback            | Unreliable on fast close ❌           |
| image | ❌ none                      | Re-dialog always ❌                   |
| ppt   | ❌ none                      | Re-dialog always ❌                   |
| link  | ❌ none                      | Re-dialog always ❌                   |
| text  | ❌ none                      | Re-dialog always ❌                   |

**Root cause:** `markContentAsViewed` was deferred to content-type-specific callbacks.
For image/ppt/link/text there was NO callback. For video, leaving before 80% skipped
the write entirely. On re-open, fresh State + no Firestore record = dialog re-appears.

**Fix:** `markContentAsViewed` is now called **immediately when the user taps "Continue"**
inside `_checkAndEnforceOneTimeView`, before the content type is even rendered. This
is universal — it applies identically to all 6 content types.

`_firestoreWrittenContentIds` prevents the 80%/render callbacks (video/PDF only)
from double-writing in the same session. Those callbacks are kept as belt-and-suspenders
for the rare case where the confirmation-time write failed silently (network error
returns `true` from the service to avoid blocking the user).

**Files changed:**
- `lib/screens/content_viewer_screen_mobile.dart` — primary write in
  `_checkAndEnforceOneTimeView` confirmed==true block; updated `_markOneTimeContentViewed`
  doc comment to reflect its new secondary role.
