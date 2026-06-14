# 📢 Content-Level and Content-Item-Level Notification Implementation

## 🎯 Overview

This document explains the implementation of **content-level** and **content-item-level** notifications, following the same pattern as course-level and module-level notifications.

---

## 📊 Notification Hierarchy

```
Course Level (notifyCourseUpdate)
    ↓
Module Level (notifyModuleUpdate)
    ↓
Content Level (notifyContentUpdate) ← NEW
    ↓
Content Item Level (notifyContentItemUpdate) ← NEW
```

---

## 🏗️ Data Structure

### Module Structure
```typescript
Module {
  id: string,
  courseId: string,
  title: string,
  description: string,
  content: {
    videos: ContentItem[],
    notes: ContentItem[],
    pdfs: ContentItem[],
    images: ContentItem[],
    ppts: ContentItem[],
    links: ContentItem[]
  }
}
```

### Content Item Structure
```typescript
ContentItem {
  id: string,
  title: string,
  description?: string,
  url?: string,
  type: 'video' | 'note' | 'pdf' | 'image' | 'ppt' | 'link',
  order?: number,
  isPublished?: boolean
}
```

---

## 🆕 New Cloud Functions

### 1. `notifyContentUpdate` - Content Type Level Changes

**Trigger**: `onDocumentWritten` on `modules/{moduleId}`

**Detects**:
- ✅ **Content Type Added**: New videos, PDFs, notes, etc. added to a module
- ✅ **Content Type Removed**: Videos, PDFs, notes, etc. removed from a module
- ✅ **Content Type Reordered**: Items within a content type rearranged

**Priority Levels**:
- 🔴 **Critical**: Content removed (e.g., "3 videos removed")
- 🟠 **Important**: Content added (e.g., "2 new PDFs added")
- 🟡 **Low**: Content reordered (e.g., "videos reordered")

**Example Notifications**:
```javascript
// Videos added
{
  type: 'content_videos_added',
  priority: 'important',
  message: '2 new videos added',
  icon: '🎥',
  contentType: 'videos',
  changeType: 'added',
  count: 2
}

// PDFs removed
{
  type: 'content_pdfs_removed',
  priority: 'critical',
  message: '1 pdf removed',
  icon: '🔴',
  contentType: 'pdfs',
  changeType: 'removed',
  count: 1
}

// Notes reordered
{
  type: 'content_notes_reordered',
  priority: 'low',
  message: 'notes reordered',
  icon: '🔄',
  contentType: 'notes',
  changeType: 'reordered',
  count: 5
}
```

---

### 2. `notifyContentItemUpdate` - Individual Item Changes

**Trigger**: `onDocumentWritten` on `modules/{moduleId}`

**Detects**:
- ✅ **Title Changed**: Content item renamed
- ✅ **Description Changed**: Content item description updated
- ✅ **URL Changed**: Content replaced (new file uploaded)
- ✅ **Published Status Changed**: Content item published/unpublished

**Priority Levels**:
- 🔴 **Critical**: Item unpublished (e.g., "Video is no longer available")
- 🟠 **Important**: Item replaced or published (e.g., "Video updated with new content")
- 🟡 **Medium**: Title changed (e.g., "Video renamed")
- 🟢 **Low**: Description changed (e.g., "Description updated")

**Example Notifications**:
```javascript
// Video title changed
{
  type: 'content_item_title_changed',
  priority: 'medium',
  message: '"Introduction to React" renamed to "React Basics"',
  icon: '✏️',
  contentType: 'videos',
  itemId: 'video_123',
  itemTitle: 'React Basics',
  changeType: 'title_changed',
  oldValue: 'Introduction to React',
  newValue: 'React Basics'
}

// Video replaced
{
  type: 'content_item_replaced',
  priority: 'important',
  message: '"React Basics" has been updated with new content',
  icon: '🔄',
  contentType: 'videos',
  itemId: 'video_123',
  itemTitle: 'React Basics',
  changeType: 'url_changed'
}

// Video unpublished
{
  type: 'content_item_unpublished',
  priority: 'critical',
  message: '"React Basics" is no longer available',
  icon: '🔴',
  contentType: 'videos',
  itemId: 'video_123',
  itemTitle: 'React Basics',
  changeType: 'unpublished'
}
```

---

## 🔄 How It Works

### Content-Level Detection Algorithm

```javascript
// For each content type (videos, pdfs, notes, etc.)
const beforeItems = beforeContent[contentType] || [];
const afterItems = afterContent[contentType] || [];

// Count changes
if (afterItems.length > beforeItems.length) {
  // Content added → Important priority
}
else if (afterItems.length < beforeItems.length) {
  // Content removed → Critical priority
}
else if (items reordered) {
  // Content reordered → Low priority
}
```

### Content-Item-Level Detection Algorithm

```javascript
// Create maps for easy lookup
const beforeMap = new Map(beforeItems.map(item => [item.id, item]));
const afterMap = new Map(afterItems.map(item => [item.id, item]));

// For each item in afterMap
for (const [itemId, afterItem] of afterMap.entries()) {
  const beforeItem = beforeMap.get(itemId);
  
  if (!beforeItem) continue; // New item (handled by content-level)
  
  // Check for changes
  if (beforeItem.title !== afterItem.title) {
    // Title changed → Medium priority
  }
  if (beforeItem.url !== afterItem.url) {
    // Content replaced → Important priority
  }
  if (beforeItem.isPublished !== afterItem.isPublished) {
    // Published status changed → Critical/Important priority
  }
}
```

---

## 📦 Update Record Structure

### Content-Level Update Record
```javascript
{
  courseId: string,
  moduleId: string,
  type: string,              // e.g., 'content_videos_added'
  message: string,           // e.g., '2 new videos added'
  priority: string,          // 'critical', 'important', 'medium', 'low'
  icon: string,              // e.g., '🎥'
  contentType: string,       // e.g., 'videos'
  changeType: string,        // 'added', 'removed', 'reordered'
  count: number,             // Number of items affected
  timestamp: Timestamp,
  notifiedUsers: string[],   // Array of user IDs
  seenBy: string[],          // Array of user IDs who have seen this
  moduleName: string,
  courseName: string
}
```

### Content-Item-Level Update Record
```javascript
{
  courseId: string,
  moduleId: string,
  contentItemId: string,     // ID of the specific content item
  type: string,              // e.g., 'content_item_title_changed'
  message: string,           // e.g., '"Video 1" renamed to "Video 2"'
  priority: string,          // 'critical', 'important', 'medium', 'low'
  icon: string,              // e.g., '✏️'
  contentType: string,       // e.g., 'videos'
  itemTitle: string,         // Current title of the item
  changeType: string,        // 'title_changed', 'url_changed', etc.
  oldValue?: string,         // Previous value (for title changes)
  newValue?: string,         // New value (for title changes)
  timestamp: Timestamp,
  notifiedUsers: string[],
  seenBy: string[],
  moduleName: string,
  courseName: string
}
```

---

## 🚀 Deployment

### 1. Deploy the Functions
```bash
cd functions
npm install
firebase deploy --only functions:notifyContentUpdate,functions:notifyContentItemUpdate
```

### 2. Verify Deployment
```bash
firebase functions:log --only notifyContentUpdate,notifyContentItemUpdate
```

---

## 🧪 Testing

### Test Content-Level Updates

1. **Add Videos to a Module**:
   - Go to Module Detail page
   - Upload 2 new videos
   - Check `contentUpdates` collection for new record
   - Verify notification sent to assigned students

2. **Remove PDFs from a Module**:
   - Delete a PDF from a module
   - Check for critical priority notification
   - Verify students receive immediate notification

3. **Reorder Content**:
   - Drag and drop videos to reorder
   - Check for low priority update (batched, not immediate)

### Test Content-Item-Level Updates

1. **Rename a Video**:
   - Edit video title in module
   - Check for medium priority notification
   - Verify update record created

2. **Replace a Video**:
   - Upload new video with same ID (replace URL)
   - Check for important priority notification
   - Verify students notified immediately

3. **Unpublish a Video**:
   - Set `isPublished: false` on a video
   - Check for critical priority notification
   - Verify immediate notification sent

---

## 📊 Priority System

### Notification Sending Rules

| Priority | Send Immediately? | Batching Strategy |
|----------|-------------------|-------------------|
| 🔴 Critical | ✅ Yes | N/A - Always immediate |
| 🟠 Important | ✅ Yes | N/A - Always immediate |
| 🟡 Medium | ❌ No | Batch every 2-4 hours |
| 🟢 Low | ❌ No | Daily digest |

### Priority Assignment

**Content-Level**:
- Added: Important
- Removed: Critical
- Reordered: Low

**Content-Item-Level**:
- Unpublished: Critical
- Replaced (URL changed): Important
- Published: Important
- Title changed: Medium
- Description changed: Low

---

## 🎨 Content Type Icons

```javascript
const icons = {
  videos: '🎥',
  notes: '📝',
  pdfs: '📄',
  images: '🖼️',
  ppts: '📊',
  links: '🔗'
};
```

---

## 🔍 Querying Updates

### Get All Content Updates for a User
```javascript
const updates = await admin.firestore()
  .collection('contentUpdates')
  .where('notifiedUsers', 'array-contains', userId)
  .where('type', '>=', 'content_')
  .where('type', '<=', 'content_~')
  .orderBy('timestamp', 'desc')
  .get();
```

### Get Unseen Content-Item Updates
```javascript
const updates = await admin.firestore()
  .collection('contentUpdates')
  .where('notifiedUsers', 'array-contains', userId)
  .where('type', '>=', 'content_item_')
  .where('type', '<=', 'content_item_~')
  .get();

const unseen = updates.docs.filter(doc => {
  const seenBy = doc.data().seenBy || [];
  return !seenBy.includes(userId);
});
```

### Get Updates by Priority
```javascript
const criticalUpdates = await admin.firestore()
  .collection('contentUpdates')
  .where('notifiedUsers', 'array-contains', userId)
  .where('priority', '==', 'critical')
  .orderBy('timestamp', 'desc')
  .limit(10)
  .get();
```

---

## 📱 Student App Integration

### Display Content Updates
```typescript
// In student app, listen to contentUpdates
const unsubscribe = firestore()
  .collection('contentUpdates')
  .where('notifiedUsers', 'array-contains', currentUserId)
  .where('seenBy', 'not-in', [currentUserId])
  .orderBy('timestamp', 'desc')
  .onSnapshot(snapshot => {
    const updates = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    // Group by priority
    const critical = updates.filter(u => u.priority === 'critical');
    const important = updates.filter(u => u.priority === 'important');
    const medium = updates.filter(u => u.priority === 'medium');
    
    // Display with appropriate UI
    displayUpdates({ critical, important, medium });
  });
```

### Mark Update as Seen
```typescript
const markAsSeen = async (updateId: string) => {
  const markUpdateAsSeen = httpsCallable(functions, 'markUpdateAsSeen');
  await markUpdateAsSeen({ updateId });
};
```

---

## 🔔 Notification Flow

```
1. Admin updates content in module
   ↓
2. Firestore trigger fires (onDocumentWritten)
   ↓
3. notifyContentUpdate / notifyContentItemUpdate analyzes changes
   ↓
4. Update record created in contentUpdates collection
   ↓
5. If priority is critical/important:
   → Notification created in notifications collection
   → sendPushNotification trigger fires
   → Push notification sent to students
   ↓
6. If priority is medium/low:
   → Update recorded for batching
   → No immediate notification
```

---

## 📈 Comparison: All Notification Levels

| Level | Function | Detects | Example |
|-------|----------|---------|---------|
| **Course** | `notifyCourseUpdate` | Course metadata changes | "Course renamed" |
| **Module** | `notifyModuleUpdate` | Module metadata, content array changes | "Module description updated" |
| **Content** | `notifyContentUpdate` | Content type additions/removals | "2 new videos added" |
| **Content Item** | `notifyContentItemUpdate` | Individual item property changes | "Video title changed" |

---

## ✅ Benefits

1. **Granular Tracking**: Students know exactly what changed
2. **Priority-Based**: Critical changes notified immediately
3. **Efficient**: Low-priority changes batched to reduce notification spam
4. **Detailed History**: Complete audit trail in `contentUpdates` collection
5. **Consistent Pattern**: Follows same structure as course/module updates

---

## 🎯 Use Cases

### Content-Level Notifications
- ✅ Admin uploads multiple videos → Students notified about new content
- ✅ Admin removes outdated PDFs → Students notified content is gone
- ✅ Admin reorders videos → Low priority, batched notification

### Content-Item-Level Notifications
- ✅ Admin fixes video title typo → Medium priority notification
- ✅ Admin replaces video with updated version → Important notification
- ✅ Admin unpublishes broken video → Critical notification
- ✅ Admin updates video description → Low priority, batched

---

## 🚨 Important Notes

### Avoiding Duplicate Notifications

The three functions (`notifyModuleUpdate`, `notifyContentUpdate`, `notifyContentItemUpdate`) all listen to the same trigger (`modules/{moduleId}`). To avoid duplicates:

1. **notifyModuleUpdate**: Detects module-level changes (title, description)
2. **notifyContentUpdate**: Detects content type changes (additions/removals/reordering)
3. **notifyContentItemUpdate**: Detects individual item changes (title, URL, etc.)

Each function checks for specific changes and returns early if no relevant changes detected.

### Performance Considerations

- All functions use `cpu: 0.5` and `memory: "256MiB"` for cost optimization
- Functions return early if no changes detected
- Batch updates for low-priority changes to reduce notification spam

---

## 📝 Next Steps

1. ✅ Deploy the new functions
2. ✅ Test with real module updates
3. ✅ Update student app to display new notification types
4. ✅ Implement batching for medium/low priority updates
5. ✅ Add analytics to track notification engagement

---

## 🎉 Summary

You now have **4 levels of content change notifications**:

1. **Course Level** → Broad changes affecting entire course
2. **Module Level** → Changes to module structure
3. **Content Level** → Changes to content types (videos, PDFs, etc.)
4. **Content Item Level** → Changes to individual content items

All following the same pattern, priority system, and notification flow! 🚀
