# 📊 Notification Levels - Quick Reference Guide

## 🎯 Overview

This guide provides a quick comparison of all 4 notification levels implemented in the system.

---

## 📋 All Notification Levels

### 1️⃣ Course Level (`notifyCourseUpdate`)

**Trigger**: `courses/{courseId}`

**Detects**:
- Course title changed
- Course description changed
- Course thumbnail changed
- Course category changed
- Course published/unpublished
- Course deleted

**Example**:
```javascript
// Before
{ title: "React Basics", published: true }

// After
{ title: "React Fundamentals", published: true }

// Notification
{
  type: 'course_title',
  priority: 'important',
  message: 'Course renamed to "React Fundamentals"',
  icon: '📚'
}
```

---

### 2️⃣ Module Level (`notifyModuleUpdate`)

**Trigger**: `modules/{moduleId}`

**Detects**:
- Module title changed
- Module description changed
- Module content array changed (any content type)

**Example**:
```javascript
// Before
{ 
  title: "Introduction",
  content: { videos: [v1, v2], pdfs: [p1] }
}

// After
{ 
  title: "Getting Started",
  content: { videos: [v1, v2, v3], pdfs: [p1] }
}

// Notification
{
  type: 'module_title',
  priority: 'important',
  message: 'Module renamed to "Getting Started"',
  icon: '📝'
}
```

---

### 3️⃣ Content Level (`notifyContentUpdate`) ⭐ NEW

**Trigger**: `modules/{moduleId}`

**Detects**:
- Content type additions (e.g., videos added)
- Content type removals (e.g., PDFs removed)
- Content type reordering

**Example**:
```javascript
// Before
{ content: { videos: [v1, v2], pdfs: [p1] } }

// After
{ content: { videos: [v1, v2, v3, v4], pdfs: [p1] } }

// Notification
{
  type: 'content_videos_added',
  priority: 'important',
  message: '2 new videos added',
  icon: '🎥',
  contentType: 'videos',
  changeType: 'added',
  count: 2
}
```

---

### 4️⃣ Content Item Level (`notifyContentItemUpdate`) ⭐ NEW

**Trigger**: `modules/{moduleId}`

**Detects**:
- Content item title changed
- Content item description changed
- Content item URL changed (content replaced)
- Content item published/unpublished

**Example**:
```javascript
// Before
{ 
  id: 'v1', 
  title: 'Intro Video', 
  url: 'old.mp4',
  isPublished: true 
}

// After
{ 
  id: 'v1', 
  title: 'Introduction Video', 
  url: 'new.mp4',
  isPublished: true 
}

// Notifications (2 separate)
[
  {
    type: 'content_item_title_changed',
    priority: 'medium',
    message: '"Intro Video" renamed to "Introduction Video"',
    icon: '✏️',
    itemId: 'v1',
    changeType: 'title_changed'
  },
  {
    type: 'content_item_replaced',
    priority: 'important',
    message: '"Introduction Video" has been updated with new content',
    icon: '🔄',
    itemId: 'v1',
    changeType: 'url_changed'
  }
]
```

---

## 🎨 Visual Hierarchy

```
📚 Course: "React Fundamentals"
    │
    ├── 📝 Module: "Getting Started"
    │       │
    │       ├── 🎥 Content Type: Videos
    │       │       │
    │       │       ├── 📹 Content Item: "Introduction Video"
    │       │       ├── 📹 Content Item: "Setup Guide"
    │       │       └── 📹 Content Item: "First Component"
    │       │
    │       ├── 📄 Content Type: PDFs
    │       │       │
    │       │       └── 📑 Content Item: "Course Notes.pdf"
    │       │
    │       └── 📝 Content Type: Notes
    │               │
    │               └── 📄 Content Item: "Key Concepts"
    │
    └── 📝 Module: "Components"
            └── ...
```

---

## 🔔 Notification Priority Matrix

| Level | Change Type | Priority | Send Immediately? |
|-------|-------------|----------|-------------------|
| **Course** | Unpublished/Deleted | 🔴 Critical | ✅ Yes |
| **Course** | Title/Description | 🟠 Important | ✅ Yes |
| **Course** | Thumbnail/Category | 🟡 Medium | ❌ Batch |
| **Module** | Title/Description | 🟠 Important | ✅ Yes |
| **Module** | Content Changed | 🟡 Medium | ❌ Batch |
| **Content** | Items Removed | 🔴 Critical | ✅ Yes |
| **Content** | Items Added | 🟠 Important | ✅ Yes |
| **Content** | Items Reordered | 🟢 Low | ❌ Daily |
| **Item** | Unpublished | 🔴 Critical | ✅ Yes |
| **Item** | Replaced/Published | 🟠 Important | ✅ Yes |
| **Item** | Title Changed | 🟡 Medium | ❌ Batch |
| **Item** | Description Changed | 🟢 Low | ❌ Daily |

---

## 📊 Change Detection Logic

### Course Level
```javascript
// Simple field comparison
if (before.title !== after.title) → Title changed
if (before.published !== after.published) → Publish status changed
```

### Module Level
```javascript
// Field comparison + content array comparison
if (before.title !== after.title) → Title changed
if (JSON.stringify(before.content) !== JSON.stringify(after.content)) → Content changed
```

### Content Level
```javascript
// Array length comparison per content type
const beforeVideos = before.content.videos || [];
const afterVideos = after.content.videos || [];

if (afterVideos.length > beforeVideos.length) → Videos added
if (afterVideos.length < beforeVideos.length) → Videos removed
if (order changed) → Videos reordered
```

### Content Item Level
```javascript
// Individual item property comparison
const beforeItem = beforeMap.get(itemId);
const afterItem = afterMap.get(itemId);

if (beforeItem.title !== afterItem.title) → Title changed
if (beforeItem.url !== afterItem.url) → Content replaced
if (beforeItem.isPublished !== afterItem.isPublished) → Publish status changed
```

---

## 🎯 When to Use Each Level

### Use Course Level When:
- ✅ Course is renamed
- ✅ Course is unpublished
- ✅ Course metadata changes
- ❌ NOT for module or content changes

### Use Module Level When:
- ✅ Module is renamed
- ✅ Module description changes
- ✅ General content changes (don't need specifics)
- ❌ NOT for specific content type or item changes

### Use Content Level When:
- ✅ Multiple videos/PDFs added at once
- ✅ Content type removed entirely
- ✅ Content reordered
- ❌ NOT for individual item property changes

### Use Content Item Level When:
- ✅ Single video title changed
- ✅ Single PDF replaced
- ✅ Single item unpublished
- ❌ NOT for bulk operations

---

## 📦 Update Record Comparison

### Course Update Record
```javascript
{
  courseId: "course123",
  type: "course_title",
  priority: "important",
  message: "Course renamed",
  icon: "📚",
  courseName: "React Fundamentals",
  courseThumb: "thumb.jpg",
  timestamp: Timestamp,
  notifiedUsers: ["user1", "user2"],
  seenBy: []
}
```

### Module Update Record
```javascript
{
  courseId: "course123",
  moduleId: "module456",
  type: "module_title",
  priority: "important",
  message: "Module renamed",
  icon: "📝",
  courseName: "React Fundamentals",
  moduleName: "Getting Started",
  timestamp: Timestamp,
  notifiedUsers: ["user1", "user2"],
  seenBy: []
}
```

### Content Update Record
```javascript
{
  courseId: "course123",
  moduleId: "module456",
  type: "content_videos_added",
  priority: "important",
  message: "2 new videos added",
  icon: "🎥",
  contentType: "videos",
  changeType: "added",
  count: 2,
  courseName: "React Fundamentals",
  moduleName: "Getting Started",
  timestamp: Timestamp,
  notifiedUsers: ["user1", "user2"],
  seenBy: []
}
```

### Content Item Update Record
```javascript
{
  courseId: "course123",
  moduleId: "module456",
  contentItemId: "video789",
  type: "content_item_title_changed",
  priority: "medium",
  message: '"Intro" renamed to "Introduction"',
  icon: "✏️",
  contentType: "videos",
  itemTitle: "Introduction",
  changeType: "title_changed",
  oldValue: "Intro",
  newValue: "Introduction",
  courseName: "React Fundamentals",
  moduleName: "Getting Started",
  timestamp: Timestamp,
  notifiedUsers: ["user1", "user2"],
  seenBy: []
}
```

---

## 🔍 Querying Examples

### Get All Updates for a Course
```javascript
// Course + Module + Content + Item updates
const updates = await firestore()
  .collection('contentUpdates')
  .where('courseId', '==', 'course123')
  .orderBy('timestamp', 'desc')
  .get();
```

### Get Only Content-Level Updates
```javascript
const contentUpdates = await firestore()
  .collection('contentUpdates')
  .where('courseId', '==', 'course123')
  .where('type', '>=', 'content_')
  .where('type', '<', 'content_item_')
  .get();
```

### Get Only Content-Item-Level Updates
```javascript
const itemUpdates = await firestore()
  .collection('contentUpdates')
  .where('courseId', '==', 'course123')
  .where('type', '>=', 'content_item_')
  .where('type', '<=', 'content_item_~')
  .get();
```

### Get Critical Updates Only
```javascript
const criticalUpdates = await firestore()
  .collection('contentUpdates')
  .where('notifiedUsers', 'array-contains', userId)
  .where('priority', '==', 'critical')
  .orderBy('timestamp', 'desc')
  .get();
```

---

## 🎨 UI Display Recommendations

### Course-Level Updates
```
📚 Course Update
React Fundamentals
"Course renamed to 'React Fundamentals'"
2 hours ago
```

### Module-Level Updates
```
📝 Module Update
React Fundamentals > Getting Started
"Module description updated"
1 hour ago
```

### Content-Level Updates
```
🎥 Content Update
React Fundamentals > Getting Started
"2 new videos added"
30 minutes ago
```

### Content-Item-Level Updates
```
✏️ Content Item Update
React Fundamentals > Getting Started
"'Intro Video' renamed to 'Introduction Video'"
5 minutes ago
```

---

## 🚀 Implementation Checklist

- [x] Course-level notifications (`notifyCourseUpdate`)
- [x] Module-level notifications (`notifyModuleUpdate`)
- [x] Content-level notifications (`notifyContentUpdate`)
- [x] Content-item-level notifications (`notifyContentItemUpdate`)
- [x] Priority system (Critical, Important, Medium, Low)
- [x] Update tracking in `contentUpdates` collection
- [x] Notification creation in `notifications` collection
- [x] Mark as seen functionality (`markUpdateAsSeen`)
- [x] Unseen count functionality (`getUnseenUpdatesCount`)
- [ ] Batching for medium/low priority updates
- [ ] Daily digest for low priority updates
- [ ] Student app UI integration
- [ ] Analytics tracking

---

## 📝 Summary

You now have **complete granularity** in content change tracking:

1. **Course Level** → Affects entire course (e.g., course renamed)
2. **Module Level** → Affects module structure (e.g., module description)
3. **Content Level** → Affects content types (e.g., 2 videos added)
4. **Content Item Level** → Affects individual items (e.g., video title changed)

Each level has its own priority system, notification flow, and use cases! 🎉
