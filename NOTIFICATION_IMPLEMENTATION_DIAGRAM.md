# 📊 Content Update Notification System - Visual Diagram

## 🎯 System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FIRESTORE TRIGGERS                          │
└─────────────────────────────────────────────────────────────────────┘

    courses/{courseId}              modules/{moduleId}
           │                               │
           │                               │
           ▼                               ▼
    ┌─────────────┐              ┌──────────────────┐
    │   Course    │              │     Module       │
    │   Update    │              │     Update       │
    │  Detected   │              │    Detected      │
    └─────────────┘              └──────────────────┘
           │                               │
           │                               ├─────────────────────┐
           │                               │                     │
           ▼                               ▼                     ▼
    ┌─────────────┐              ┌──────────────┐      ┌──────────────┐
    │   Course    │              │   Module     │      │   Content    │
    │    Level    │              │    Level     │      │    Level     │
    │  notifyCo-  │              │  notifyMo-   │      │  notifyCo-   │
    │  urseUpdate │              │  duleUpdate  │      │  ntentUpdate │
    └─────────────┘              └──────────────┘      └──────────────┘
           │                               │                     │
           │                               │                     │
           │                               │                     ▼
           │                               │            ┌──────────────┐
           │                               │            │Content Item  │
           │                               │            │    Level     │
           │                               │            │notifyContent │
           │                               │            │ ItemUpdate   │
           │                               │            └──────────────┘
           │                               │                     │
           └───────────────┬───────────────┴─────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   Priority Analysis    │
              │  Critical | Important  │
              │   Medium  |    Low     │
              └────────────────────────┘
                           │
                ┌──────────┴──────────┐
                │                     │
                ▼                     ▼
    ┌─────────────────────┐  ┌─────────────────┐
    │  contentUpdates     │  │  notifications  │
    │    Collection       │  │   Collection    │
    │  (All Updates)      │  │ (Critical/Imp)  │
    └─────────────────────┘  └─────────────────┘
                │                     │
                │                     ▼
                │            ┌─────────────────┐
                │            │ sendPushNoti-   │
                │            │   fication      │
                │            │    Trigger      │
                │            └─────────────────┘
                │                     │
                │                     ▼
                │            ┌─────────────────┐
                │            │  FCM Push to    │
                │            │    Students     │
                │            └─────────────────┘
                │
                ▼
    ┌─────────────────────┐
    │   Student App       │
    │  Displays Updates   │
    │   with Priority     │
    └─────────────────────┘
```

---

## 🔄 Change Detection Flow

### Course Level Detection

```
Admin Updates Course
        │
        ▼
┌───────────────────┐
│  Before Data      │
│  title: "React"   │
│  published: true  │
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  After Data       │
│  title: "React+"  │
│  published: true  │
└───────────────────┘
        │
        ▼
┌───────────────────────────┐
│  Comparison Logic         │
│  before.title !== after   │
│  → Title Changed          │
└───────────────────────────┘
        │
        ▼
┌───────────────────────────┐
│  Priority: Important      │
│  Type: course_title       │
│  Message: "Course renamed"│
└───────────────────────────┘
        │
        ▼
┌───────────────────────────┐
│  Create Update Record     │
│  Send Notification        │
└───────────────────────────┘
```

---

### Content Level Detection

```
Admin Adds Videos to Module
        │
        ▼
┌─────────────────────────┐
│  Before Content         │
│  videos: [v1, v2]       │
│  pdfs: [p1]             │
└─────────────────────────┘
        │
        ▼
┌─────────────────────────┐
│  After Content          │
│  videos: [v1,v2,v3,v4]  │
│  pdfs: [p1]             │
└─────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│  For Each Content Type:         │
│  videos: 4 - 2 = 2 added        │
│  pdfs: 1 - 1 = 0 (no change)    │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│  Priority: Important            │
│  Type: content_videos_added     │
│  Message: "2 new videos added"  │
│  Icon: 🎥                        │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│  Create Update Record           │
│  Send Notification              │
└─────────────────────────────────┘
```

---

### Content Item Level Detection

```
Admin Renames Video
        │
        ▼
┌─────────────────────────┐
│  Before Item            │
│  id: "v1"               │
│  title: "Intro"         │
│  url: "video.mp4"       │
└─────────────────────────┘
        │
        ▼
┌─────────────────────────┐
│  After Item             │
│  id: "v1"               │
│  title: "Introduction"  │
│  url: "video.mp4"       │
└─────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  Item-by-Item Comparison:           │
│  Map items by ID                    │
│  Compare properties                 │
│  → Title changed                    │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  Priority: Medium                   │
│  Type: content_item_title_changed   │
│  Message: "Intro → Introduction"    │
│  Icon: ✏️                            │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  Create Update Record               │
│  Batch for Later (Medium Priority)  │
└─────────────────────────────────────┘
```

---

## 🎯 Priority-Based Routing

```
                    ┌─────────────────┐
                    │  Update Detected│
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Analyze Priority│
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   CRITICAL   │    │  IMPORTANT   │    │ MEDIUM / LOW │
│              │    │              │    │              │
│ • Unpublish  │    │ • New Content│    │ • Reorder    │
│ • Delete     │    │ • Replace    │    │ • Title Edit │
│ • Remove     │    │ • Rename     │    │ • Description│
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                    │
       ▼                   ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│Send Immediate│    │Send Immediate│    │  Queue for   │
│Notification  │    │Notification  │    │   Batching   │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                    │
       └───────────────────┴────────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  Student Sees   │
                  │   Notification  │
                  └─────────────────┘
```

---

## 📊 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        ADMIN APP                                │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Edit Course  │  │ Edit Module  │  │ Edit Content │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
└─────────┼──────────────────┼──────────────────┼────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                       FIRESTORE                                 │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   courses/   │  │   modules/   │  │   modules/   │         │
│  │  {courseId}  │  │  {moduleId}  │  │  {moduleId}  │         │
│  │   updated    │  │   updated    │  │   updated    │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
└─────────┼──────────────────┼──────────────────┼────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CLOUD FUNCTIONS                               │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │notifyCourse  │  │notifyModule  │  │notifyContent │         │
│  │   Update     │  │   Update     │  │   Update     │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                  │                  │                 │
│         │                  │         ┌────────┴────────┐        │
│         │                  │         │notifyContentItem│        │
│         │                  │         │     Update      │        │
│         │                  │         └────────┬────────┘        │
└─────────┼──────────────────┼──────────────────┼────────────────┘
          │                  │                  │
          └──────────────────┴──────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                       FIRESTORE                                 │
│                                                                 │
│  ┌──────────────────────────────────────────────────┐          │
│  │           contentUpdates Collection              │          │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐   │          │
│  │  │  Course    │ │  Module    │ │  Content   │   │          │
│  │  │  Updates   │ │  Updates   │ │  Updates   │   │          │
│  │  └────────────┘ └────────────┘ └────────────┘   │          │
│  └──────────────────────────────────────────────────┘          │
│                                                                 │
│  ┌──────────────────────────────────────────────────┐          │
│  │           notifications Collection               │          │
│  │  (Only Critical & Important Priority)            │          │
│  └──────────────────────┬───────────────────────────┘          │
└─────────────────────────┼──────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CLOUD FUNCTIONS                               │
│                                                                 │
│  ┌──────────────────────────────────────────────────┐          │
│  │         sendPushNotification Trigger             │          │
│  │  (Listens to notifications collection)           │          │
│  └──────────────────────┬───────────────────────────┘          │
└─────────────────────────┼──────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   FIREBASE MESSAGING                            │
│                                                                 │
│  ┌──────────────────────────────────────────────────┐          │
│  │         FCM Push Notification Service            │          │
│  └──────────────────────┬───────────────────────────┘          │
└─────────────────────────┼──────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      STUDENT APP                                │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Push Notif.  │  │ In-App Badge │  │ Updates List │         │
│  │  Received    │  │   Updated    │  │   Displayed  │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔍 Update Record Structure Comparison

```
┌─────────────────────────────────────────────────────────────────┐
│                    COURSE UPDATE RECORD                         │
├─────────────────────────────────────────────────────────────────┤
│ courseId         │ "course123"                                  │
│ type             │ "course_title"                               │
│ priority         │ "important"                                  │
│ message          │ "Course renamed"                             │
│ icon             │ "📚"                                          │
│ courseName       │ "React Fundamentals"                         │
│ courseThumb      │ "thumb.jpg"                                  │
│ timestamp        │ Timestamp                                    │
│ notifiedUsers    │ ["user1", "user2"]                           │
│ seenBy           │ []                                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    MODULE UPDATE RECORD                         │
├─────────────────────────────────────────────────────────────────┤
│ courseId         │ "course123"                                  │
│ moduleId         │ "module456"                                  │
│ type             │ "module_title"                               │
│ priority         │ "important"                                  │
│ message          │ "Module renamed"                             │
│ icon             │ "📝"                                          │
│ courseName       │ "React Fundamentals"                         │
│ moduleName       │ "Getting Started"                            │
│ timestamp        │ Timestamp                                    │
│ notifiedUsers    │ ["user1", "user2"]                           │
│ seenBy           │ []                                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   CONTENT UPDATE RECORD                         │
├─────────────────────────────────────────────────────────────────┤
│ courseId         │ "course123"                                  │
│ moduleId         │ "module456"                                  │
│ type             │ "content_videos_added"                       │
│ priority         │ "important"                                  │
│ message          │ "2 new videos added"                         │
│ icon             │ "🎥"                                          │
│ contentType      │ "videos"                                     │
│ changeType       │ "added"                                      │
│ count            │ 2                                            │
│ courseName       │ "React Fundamentals"                         │
│ moduleName       │ "Getting Started"                            │
│ timestamp        │ Timestamp                                    │
│ notifiedUsers    │ ["user1", "user2"]                           │
│ seenBy           │ []                                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                CONTENT ITEM UPDATE RECORD                       │
├─────────────────────────────────────────────────────────────────┤
│ courseId         │ "course123"                                  │
│ moduleId         │ "module456"                                  │
│ contentItemId    │ "video789"                                   │
│ type             │ "content_item_title_changed"                 │
│ priority         │ "medium"                                     │
│ message          │ "Intro → Introduction"                       │
│ icon             │ "✏️"                                          │
│ contentType      │ "videos"                                     │
│ itemTitle        │ "Introduction"                               │
│ changeType       │ "title_changed"                              │
│ oldValue         │ "Intro"                                      │
│ newValue         │ "Introduction"                               │
│ courseName       │ "React Fundamentals"                         │
│ moduleName       │ "Getting Started"                            │
│ timestamp        │ Timestamp                                    │
│ notifiedUsers    │ ["user1", "user2"]                           │
│ seenBy           │ []                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎨 Student App UI Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      STUDENT APP HOME                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────┐          │
│  │  🔔 Updates (3 new)                              │          │
│  │                                                  │          │
│  │  🔴 CRITICAL                                     │          │
│  │  ┌────────────────────────────────────────────┐ │          │
│  │  │ 📚 React Fundamentals                      │ │          │
│  │  │ ⚠️ Course unpublished                       │ │          │
│  │  │ 5 minutes ago                              │ │          │
│  │  └────────────────────────────────────────────┘ │          │
│  │                                                  │          │
│  │  🟠 IMPORTANT                                    │          │
│  │  ┌────────────────────────────────────────────┐ │          │
│  │  │ 🎥 React Fundamentals > Getting Started   │ │          │
│  │  │ 2 new videos added                         │ │          │
│  │  │ 30 minutes ago                             │ │          │
│  │  └────────────────────────────────────────────┘ │          │
│  │                                                  │          │
│  │  🟡 MEDIUM                                       │          │
│  │  ┌────────────────────────────────────────────┐ │          │
│  │  │ ✏️ React Fundamentals > Getting Started   │ │          │
│  │  │ "Intro" renamed to "Introduction"          │ │          │
│  │  │ 1 hour ago                                 │ │          │
│  │  └────────────────────────────────────────────┘ │          │
│  │                                                  │          │
│  └──────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📈 Scalability Considerations

```
┌─────────────────────────────────────────────────────────────────┐
│                    FUNCTION EXECUTION                           │
│                                                                 │
│  Course Update:  ~100-200ms  (Simple field comparison)         │
│  Module Update:  ~200-400ms  (Content array comparison)        │
│  Content Update: ~300-600ms  (Multiple array comparisons)      │
│  Item Update:    ~400-800ms  (Item-by-item comparison)         │
│                                                                 │
│  All functions use:                                             │
│  - cpu: 0.5                                                     │
│  - memory: "256MiB"                                             │
│  - Early return if no changes                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    OPTIMIZATION STRATEGIES                      │
│                                                                 │
│  ✅ Early return if no relevant changes                         │
│  ✅ Batch notifications for low priority                        │
│  ✅ Deduplicate by platform (iOS/Android)                       │
│  ✅ Limit to assigned users only                                │
│  ✅ Use indexes for efficient queries                           │
└─────────────────────────────────────────────────────────────────┘
```

---

This visual diagram should help you understand the complete flow of the notification system from admin action to student notification! 🚀
