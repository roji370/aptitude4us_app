import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../utils/logger.dart';
import '../models/user_model.dart';
import '../utils/adaptive_navigation.dart';
import 'login_screen.dart';
import '../utils/tab_notifier.dart';
import '../providers/session_provider.dart';
import 'chat_screen.dart';
import 'community_chat_screen.dart';
import 'past_questions_screen.dart';
import 'dart:async';
import 'terms_conditions_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<UserModel?>? _userDataFuture;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    // Cache the future to prevent re-firing on rebuild
    _userDataFuture = Provider.of<AuthService>(context, listen: false).getUserData();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}';
        });
      }
    } catch (e) {
      Logger.e('Could not load app version: $e');
    }
  }

  Future<void> _logout() async {
    if (!mounted) return;

    bool dialogShown = false;

    try {
      // Show loading indicator
      if (!mounted) return;

      dialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
            ),
          );
        },
      );

      if (!mounted) return;

      final authService = Provider.of<AuthService>(context, listen: false);

      // Try normal logout with a timeout
      bool logoutCompleted = false;

      // Create a completer to track emergency logout
      final emergencyCompleter = Completer<void>();

      // Start a timer for timeout
      Future.delayed(const Duration(seconds: 5), () async {
        if (!logoutCompleted) {
          Logger.w("Logout timeout, using emergency logout");
          try {
            await authService.emergencySignOut();
            logoutCompleted = true;
            if (!emergencyCompleter.isCompleted) {
              emergencyCompleter.complete();
            }
          } catch (e) {
            Logger.e("Error in emergency logout: $e");
            if (!emergencyCompleter.isCompleted) {
              emergencyCompleter.completeError(e);
            }
          }
        }
      });

      // Try normal logout
      try {
        await authService.signOut();
        logoutCompleted = true;
      } catch (e) {
        // Wait for emergency logout to complete if it's running
        if (!logoutCompleted && !emergencyCompleter.isCompleted) {
          await emergencyCompleter.future;
        } else if (!logoutCompleted) {
          // If emergency logout hasn't started yet, do it now
          await authService.emergencySignOut();
          logoutCompleted = true;
        }
      }

      // Close the dialog if it was shown
      if (dialogShown && mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }

      // Reset tab notifier so the next login starts on Home tab
      activeTabNotifier.value = 0;

      // Clear session provider state (subscription cache, observers, epoch)
      if (mounted) {
        try {
          Provider.of<SessionProvider>(context, listen: false).clear();
        } catch (e) {
          Logger.e('Error clearing session provider (non-fatal): $e');
        }
      }

      // Navigate to login screen
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      Logger.e('Error during logout: $e');

      // Close the loading dialog if it was open
      if (dialogShown && mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }

      // Show error message if still mounted
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not sign out. Please restart the app.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _logout(); // Perform logout
              },
              child: const Text(
                'Logout',
                style: TextStyle(color: Color(0xFF1565C0)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUserId = authService.currentUser?.uid;

    if (currentUserId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Please log in to view your profile'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await AuthPersistenceService.clearAll();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<UserModel?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1565C0),
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }

        final userData = snapshot.data;

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            children: [
              // Top Profile Header Section
              _buildProfileHeader(context, userData),

              // Bottom Content Section
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 40, // account for padding
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  const SizedBox(height: 10),

                                  // Menu Items
                                  _buildMenuItem(
                                    context,
                                    Icons.settings,
                                    'Manage Profile',
                                    () {
                                      // Navigate to Manage Profile with smooth transition
                                      AdaptiveNavigation.pushNamed(context, '/settings');
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMenuItem(
                                    context,
                                    Icons.person_outline,
                                    'Student Details',
                                    () {
                                      AdaptiveNavigation.navigateTo(
                                        context: context,
                                        page: const CommunityChatScreen(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMenuItem(
                                    context,
                                    Icons.quiz_outlined,
                                    'Past Questions',
                                    () {
                                      AdaptiveNavigation.navigateTo(
                                        context: context,
                                        page: const PastQuestionsScreen(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMenuItem(
                                    context,
                                    Icons.chat_bubble_outline,
                                    'Chat With Admin',
                                    () {
                                      AdaptiveNavigation.navigateTo(
                                        context: context,
                                        page: const ChatScreen(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMenuItem(
                                    context,
                                    Icons.description_outlined,
                                    'Terms And Conditions',
                                    () {
                                      AdaptiveNavigation.navigateTo(
                                        context: context,
                                        page: const TermsConditionsScreen(),
                                      );
                                    },
                                  ),
                                ],
                              ),

                              // Logout Button at bottom
                              Column(
                                children: [
                                  const SizedBox(height: 16),
                                  _buildLogoutButton(context),
                                  const SizedBox(height: 6),
                                  if (_appVersion.isNotEmpty)
                                    Text(
                                      _appVersion,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(BuildContext context, UserModel? userData) {
    final photoUrl = userData?.photoUrl;
    
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1565C0),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            children: [
              // Back button and Title
              Row(
                children: [
                  const SizedBox(width: 48), // Balance spacing
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance spacing
                ],
              ),
              const SizedBox(height: 8),

              // Profile Picture
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  color: Colors.white.withOpacity(0.3),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.account_circle,
                              size: 84,
                              color: Colors.white,
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            );
                          },
                        )
                      : const Icon(
                          Icons.account_circle,
                          size: 84,
                          color: Colors.white,
                        ),
                ),
              ),
              const SizedBox(height: 10),

              // Name
              Text(
                userData?.displayName ?? 'User',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),

              // Email
              Text(
                userData?.email ?? 'user@example.com',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.black87,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward,
              color: Colors.black87,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return ElevatedButton(
      onPressed: _showLogoutDialog,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
        elevation: 3,
      ),
      child: const Text(
        'Logout',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
