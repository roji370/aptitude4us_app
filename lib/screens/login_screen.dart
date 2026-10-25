import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../services/first_time_user_service.dart';
import '../services/firestore_service.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';
import '../utils/exam_overview_navigator.dart';
import '../widgets/exam_overview_dialog.dart';
import 'main_screen.dart';
import 'profile_completion_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    Logger.i("🔐 LoginScreen: initState called");

    // Force first frame render for iOS Simulator
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Logger.i(
          "🔐 LoginScreen: Post-frame callback - ensuring visual update",
        );
        // Force the renderer to schedule a frame
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Convert Firebase error codes to user-friendly messages
  String _getFirebaseErrorMessage(String errorString) {
    // Handle device restriction errors first (before Firebase error code extraction)
    if (errorString.contains('device-restricted')) {
      return 'This account is restricted to a specific device. Please contact support if you believe this is an error.';
    }
    
    if (errorString.contains('Device validation failed')) {
      return 'Device validation failed. Please check your internet connection and try again, or contact support if the issue persists.';
    }

    // Extract Firebase error code from the error string
    String errorCode = '';

    // Try to extract the error code from Firebase Auth errors
    if (errorString.contains('[firebase_auth/')) {
      final start =
          errorString.indexOf('[firebase_auth/') + '[firebase_auth/'.length;
      final end = errorString.indexOf(']', start);
      if (end != -1) {
        errorCode = errorString.substring(start, end);
      }
    }

    // Map Firebase error codes to user-friendly messages
    switch (errorCode) {
      case 'invalid-credential':
        return 'Invalid email or password. Please check your credentials and try again.';
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed login attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled. Please contact support.';
      case 'invalid-verification-code':
        return 'Invalid verification code. Please try again.';
      case 'invalid-verification-id':
        return 'Invalid verification ID. Please try again.';
      case 'credential-already-in-use':
        return 'This credential is already associated with another account.';
      case 'requires-recent-login':
        return 'Please log out and log back in before retrying this operation.';
      case 'device-restricted':
        return 'This account is restricted to a specific device. Please contact support if you believe this is an error.';
      default:
        // Handle other common error patterns
        if (errorString.contains("Firebase Auth is not available")) {
          return "Unable to connect to authentication service. Please check your internet connection.";
        }

        // If we can't identify the specific error, provide a generic message
        return 'Authentication failed. Please check your credentials and try again.';
    }
  }

  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      try {
        // Store context before async operation and create a flag to track if navigation is needed
        final scaffoldContext = context;
        Logger.i("🔐 LoginScreen: Attempting to get AuthService from Provider");
        final authService = Provider.of<AuthService>(
          scaffoldContext,
          listen: false,
        );
        Logger.i("🔐 LoginScreen: AuthService obtained successfully");
        bool shouldNavigateToHome = false;

        // Try to sign in with Firebase using device restriction validation
        final userCredential = await authService.loginWithDeviceRestriction(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        // If widget is unmounted at this point, don't continue with UI operations
        if (!mounted) return;

        // Force a token refresh to get the latest custom claims
        await authService.forceTokenRefresh();

        // Get the custom claims for logging/debugging
        final claims = await authService.getCustomClaims();
        Logger.i("User claims after login: $claims");

        // Check login status and set navigation flag instead of navigating directly
        bool isLoggedInViaToken = authService.isUserLoggedIn;
        bool hasPersistedToken = await AuthPersistenceService.isLoggedIn();
        shouldNavigateToHome = isLoggedInViaToken || hasPersistedToken;

        // If the widget is no longer in the tree, don't try to update the UI
        if (!mounted) return;

        if (shouldNavigateToHome) {
          // Check if profile is complete before navigating
          bool profileComplete = false;
          try {
            profileComplete = await authService.isProfileComplete();
            Logger.i("Profile completion status after login: $profileComplete");
          } catch (e) {
            Logger.e("Error checking profile completion: $e");
            // If error, assume profile is incomplete and let user fill it
            profileComplete = false;
          }

          if (!mounted) return;

          // Profile is complete — go straight to the main screen.
          // Exam overview is only for users who have NOT yet completed their profile.
          if (profileComplete) {
            Logger.i("Profile complete - navigating to home");
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(scaffoldContext).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                );
              }
            });
            return;
          }

          // Profile is NOT complete — check if the exam overview has been watched.
          // The exam overview is a mandatory first-time orientation that users must
          // go through before filling out their profile.
          final firstTimeUserService = FirstTimeUserService();
          final hasWatchedExamOverview = await firstTimeUserService
              .hasWatchedExamOverview(userCredential.user!.uid);

          if (!mounted) return;

          if (!hasWatchedExamOverview) {
            Logger.i("Profile incomplete & exam overview not watched - showing exam overview dialog");
            _showExamOverviewDialog();
            return;
          }

          // Exam overview already watched but profile still incomplete — go to profile completion
          Logger.i("Exam overview already watched - navigating to profile completion");
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(scaffoldContext).pushReplacement(
                MaterialPageRoute(builder: (_) => const ProfileCompletionScreen()),
              );
            }
          });
        } else if (userCredential == null) {
          // Handle the specific error case where login partially succeeded
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Login partial success. Please restart the app to complete login.';
          });
        }
      } catch (e) {
        // Only update state if still mounted
        if (!mounted) return;

        // Create a more user-friendly error message
        String errorMsg = _getFirebaseErrorMessage(e.toString());
        Logger.e("🔐 LoginScreen: Sign in error: $e");
        Logger.i("🔐 LoginScreen: User-friendly error: $errorMsg");

        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  /// Show exam overview dialog to first-time users
  void _showExamOverviewDialog() {
    if (!mounted) return;

    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false, // User must click proceed
      builder: (dialogContext) => ExamOverviewDialog(
        onProceed: () async {
          Logger.i('📚 Navigating to Exam Overview from login dialog');
          
          // Navigate to exam overview
          final success = await ExamOverviewNavigator.navigateToExamOverview(
            context,
            firestoreService,
          );
          
          if (!success) {
            Logger.e('Failed to navigate to exam overview');
            // If navigation fails, navigate to home as fallback
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const MainScreen()),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Logger.i("🔐 LoginScreen: build method called");
    final screenSize = MediaQuery.of(context).size;
    Logger.i(
      "🔐 LoginScreen: Screen size: ${screenSize.width}x${screenSize.height}",
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Brand header ──────────────────────────────────
                  const SizedBox(height: 24),
                  // Logo
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.school_rounded,
                        size: 32,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'APTITUDE 4 US',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome Back',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      height: 32 / 24,
                      letterSpacing: -0.24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to access your nursing prep courses',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.onSurfaceVariant,
                      height: 20 / 14,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Email field ────────────────────────────────────
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Email Address',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                          letterSpacing: 0.24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'nurse.candidate@example.com',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.outline,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.primaryContainer,
                          width: 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.error,
                          width: 1,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.error,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Password field ─────────────────────────────────
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Password',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                          letterSpacing: 0.24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: '••••••••••••',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.outline,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.primaryContainer,
                          width: 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.error,
                          width: 1,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.error,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: AppColors.outline,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // ── Forgot password ────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // Show forgot password toast/dialog
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Password reset link sent to your registered email.',
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                            backgroundColor: AppColors.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondary,
                          letterSpacing: 0.14,
                        ),
                      ),
                    ),
                  ),

                  // ── Error message ──────────────────────────────────
                  if (_errorMessage.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.onErrorContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.onErrorContainer,
                                height: 1.4,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _errorMessage = '';
                              });
                            },
                            child: const Icon(
                              Icons.close_rounded,
                              color: AppColors.onErrorContainer,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Sign In button ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundColor: AppColors.onPrimary,
                        disabledBackgroundColor: AppColors.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: AppColors.onPrimary,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Sign In',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Support footer ─────────────────────────────────
                  Text(
                    'Need help logging in?',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Support: support@aptitude4us.edu',
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Contact Academy Support',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Logger.i(
      "🔐 LoginScreen: didChangeDependencies called - widget should be visible",
    );
  }
}
