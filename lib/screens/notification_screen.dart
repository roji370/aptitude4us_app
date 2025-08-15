import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import 'package:intl/intl.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _selectedCategory = 'all';

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting notification: $e')),
        );
      }
    }
  }

  List<QueryDocumentSnapshot> _groupNotificationsByDate(
    List<QueryDocumentSnapshot> notifications,
  ) {
    // Sort notifications by timestamp (newest first)
    notifications.sort((a, b) {
      final aTimestamp =
          (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp;
      final bTimestamp =
          (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });

    return notifications;
  }

  String _getDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final notificationDate = DateTime(date.year, date.month, date.day);

    if (notificationDate == today) {
      return 'Today';
    } else if (notificationDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMMM d, y').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final currentUser = Provider.of<AuthService>(context).currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF323483),
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _selectedCategory = value);
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'all',
                    child: Text('All Notifications'),
                  ),
                  const PopupMenuItem(
                    value: 'chat',
                    child: Text('Chat Notifications'),
                  ),
                  const PopupMenuItem(
                    value: 'system',
                    child: Text('System Notifications'),
                  ),
                ],
          ),
        ],
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: currentUser?.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var notifications = snapshot.data!.docs;

            // Filter by category
            if (_selectedCategory != 'all') {
              notifications =
                  notifications.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['type'] == _selectedCategory;
                  }).toList();
            }

            if (notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notifications yet',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Group notifications by date
            final groupedNotifications = _groupNotificationsByDate(
              notifications,
            );
            DateTime? currentDate;

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + safeAreaBottom),
              itemCount: groupedNotifications.length,
              itemBuilder: (context, index) {
                final notification =
                    groupedNotifications[index].data() as Map<String, dynamic>;
                final timestamp = notification['timestamp'] as Timestamp;
                final date = timestamp.toDate();

                // Check if we need to show a date header
                final showHeader = currentDate?.day != date.day;
                if (showHeader) {
                  currentDate = date;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader) ...[
                      if (index > 0) const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _getDateHeader(date),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                    Dismissible(
                      key: Key(groupedNotifications[index].id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) {
                        _deleteNotification(groupedNotifications[index].id);
                      },
                      child: Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: const Color(0xFFC9C8D8),
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            if (notification['type'] == 'chat') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ChatScreen(),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF323483,
                                    ).withAlpha(26),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    notification['type'] == 'chat'
                                        ? Icons.chat_bubble_outline
                                        : Icons.notifications_none,
                                    color: const Color(0xFF323483),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notification['title'] ?? 'Notification',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF323483),
                                        ),
                                      ),
                                      if (notification['body'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          notification['body'],
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTimestamp(timestamp),
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final diff = now.difference(date);

    if (diff.inDays > 7) {
      return DateFormat('MMM d, y').format(date);
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
