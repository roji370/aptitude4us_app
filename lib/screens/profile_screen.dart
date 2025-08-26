import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../widgets/custom_bottom_navigation.dart';
import 'login_screen.dart';
import 'assigned_courses_screen.dart';
import 'chat_screen.dart';
import 'community_chat_screen.dart';
import 'dart:async';
import 'terms_conditions_screen.dart';

// Navigation helper functions that avoid BuildContext across async gaps issues
void _safeNavigatePushAndRemoveUntil(BuildContext context, Widget page) {
  if (!context.mounted) return;

  // Navigate in a safe manner that works even after async operations
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => page),
        (route) => false,
      );
    }
  });
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedIndex = 1; // Profile tab selected by default
  bool _isLoading = false;

  Future<void> _logout() async {
    if (!mounted) return;

    bool dialogShown = false;

    try {
      // Show loading indicator
      if (!mounted) return; // Exit if not mounted

      dialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF323483)),
            ),
          );
        },
      );

      if (!mounted) return; // Check again after dialog shown

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
        // Use mounted check and navigate safely
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }

      // Navigate to login screen
      if (mounted) {
        // Use proper WidgetsBinding.instance to avoid context issues
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
        // Use ScaffoldMessenger directly with a post-frame callback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not sign out. Please restart the app.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    CustomBottomNavigation.handleNavigation(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;

    // Get screen dimensions for responsiveness
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 16),
                    // User Profile Card
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.05,
                      ),
                      child: Container(
                        width: double.infinity,
                        height: screenSize.height * 0.18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF323483),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFC9C8D8),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F171A1F),
                              offset: Offset(0, 0),
                              blurRadius: 2,
                            ),
                            BoxShadow(
                              color: Color(0x12171A1F),
                              offset: Offset(0, 0),
                              blurRadius: 1,
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // User icon
                            Positioned(
                              top: screenSize.height * 0.045,
                              left: screenSize.width * 0.05,
                              child: Icon(
                                Icons.account_circle,
                                size: screenSize.width * 0.12,
                                color: Colors.white,
                              ),
                            ),

                            // User's name
                            Positioned(
                              top: screenSize.height * 0.05,
                              left: screenSize.width * 0.2,
                              child: Text(
                                currentUser?.displayName ?? "User",
                                style: GoogleFonts.archivo(
                                  fontSize: screenSize.width * 0.06,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),

                            // Email
                            Positioned(
                              top: screenSize.height * 0.09,
                              left: screenSize.width * 0.2,
                              child: Text(
                                currentUser?.email ?? "user@example.com",
                                style: GoogleFonts.inter(
                                  fontSize: screenSize.width * 0.04,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.03),

                    // Chat Card
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.05,
                      ),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: const Color(0xFFC9C8D8),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF323483).withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.chat_outlined,
                              color: const Color(0xFF323483),
                              size: screenSize.width * 0.06,
                            ),
                          ),
                          title: Text(
                            'Chat with Admin',
                            style: GoogleFonts.inter(
                              fontSize: screenSize.width * 0.045,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF323483),
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            color: const Color(0xFF323483),
                            size: screenSize.width * 0.05,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChatScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.02),

                    // Student Details Card
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.05,
                      ),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: const Color(0xFFC9C8D8),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF323483).withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.groups_outlined,
                              color: const Color(0xFF323483),
                              size: screenSize.width * 0.06,
                            ),
                          ),
                          title: Text(
                            'Student Details',
                            style: GoogleFonts.inter(
                              fontSize: screenSize.width * 0.045,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF323483),
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            color: const Color(0xFF323483),
                            size: screenSize.width * 0.05,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CommunityChatScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.02),

                    // Settings Card
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.05,
                      ),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: const Color(0xFFC9C8D8),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF323483).withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.settings_outlined,
                              color: const Color(0xFF323483),
                              size: screenSize.width * 0.06,
                            ),
                          ),
                          title: Text(
                            'Settings',
                            style: GoogleFonts.inter(
                              fontSize: screenSize.width * 0.045,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF323483),
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            color: const Color(0xFF323483),
                            size: screenSize.width * 0.05,
                          ),
                          onTap: () {
                            Navigator.pushNamed(context, '/settings');
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.02),

                    // Terms & Conditions Card
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.05,
                      ),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: const Color(0xFFC9C8D8),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF323483).withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.description_outlined,
                              color: const Color(0xFF323483),
                              size: screenSize.width * 0.06,
                            ),
                          ),
                          title: Text(
                            'Terms & Conditions',
                            style: GoogleFonts.inter(
                              fontSize: screenSize.width * 0.045,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF323483),
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            color: const Color(0xFF323483),
                            size: screenSize.width * 0.05,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TermsConditionsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.03),

                    // Log Out Button
                    ElevatedButton(
                      onPressed: _logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF323483),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: screenSize.width * 0.08,
                          vertical: screenSize.height * 0.015,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        "Log Out",
                        style: GoogleFonts.inter(
                          fontSize: screenSize.width * 0.04,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.03),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavigation(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          CustomBottomNavigation.handleNavigation(context, index);
        },
      ),
    );
  }
}
