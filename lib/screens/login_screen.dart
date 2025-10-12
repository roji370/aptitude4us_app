import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../utils/logger.dart';
import 'assigned_courses_screen.dart';

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
          // Use WidgetsBinding.instance.addPostFrameCallback to safely navigate after the current frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(scaffoldContext).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const AssignedCoursesScreen(),
                ),
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

  @override
  Widget build(BuildContext context) {
    Logger.i("🔐 LoginScreen: build method called");
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    Logger.i(
      "🔐 LoginScreen: Screen size: ${screenSize.width}x${screenSize.height}",
    );

    // Increase field height for better visibility and prevent shrinking
    final fieldHeight = screenSize.height * 0.075;

    return Scaffold(
      backgroundColor: const Color(0xFF1C1A5E),
      body: SafeArea(
        // Don't add padding at the top to allow the blue background to extend fully
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Container(
              width: screenSize.width,
              // Adjust the height to account for status bar and bottom safe area
              height: screenSize.height,
              color: const Color(
                0xFF1C1A5E,
              ), // Background color for top section
              child: Stack(
                children: [
                  // White container with rounded top corners - positioned to match design
                  Positioned(
                    top: screenSize.height * 0.42,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(25),
                          topRight: Radius.circular(25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x1F171A1F),
                            offset: Offset(0, -3),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Title: "Briffini Academy"
                  Positioned(
                    top: screenSize.height * 0.08,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Briffini Academy",
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: GoogleFonts.archivo(
                            fontSize: screenSize.width * 0.095,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Image: Treasure chest - positioned higher to match design
                  Positioned(
                    top: screenSize.height * 0.16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: screenSize.width * 0.5,
                        height: screenSize.width * 0.5,
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(
                              'assets/images/treasure_chest.png',
                            ),
                            fit: BoxFit.contain,
                            onError: null, // Handle missing image gracefully
                          ),
                        ),
                        child: const Icon(
                          Icons.school,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                  ),

                  // Email Text Field - positioned in white container
                  Positioned(
                    top: screenSize.height * 0.45,
                    left: screenSize.width * 0.06,
                    right: screenSize.width * 0.06,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Email",
                          style: GoogleFonts.inter(
                            fontSize: screenSize.width * 0.045,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF171A1F),
                          ),
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          height: fieldHeight,
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(
                              fontSize: screenSize.width * 0.045,
                              color: const Color(0xFF171A1F),
                            ),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: screenSize.width * 0.04,
                                vertical: fieldHeight * 0.25,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Color(0xFF636AE8),
                                  width: 1,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Color(0xFF636AE8),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Color(0xFF636AE8),
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 1,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                              errorStyle: TextStyle(
                                color: Colors.red,
                                fontSize: screenSize.width * 0.035,
                                height: 0.5,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              return null;
                            },
                          ),
                        ),
                        SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // Password Text Field
                  Positioned(
                    top: screenSize.height * 0.57,
                    left: screenSize.width * 0.06,
                    right: screenSize.width * 0.06,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Password",
                          style: GoogleFonts.inter(
                            fontSize: screenSize.width * 0.045,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF171A1F),
                          ),
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          height: fieldHeight,
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            style: TextStyle(
                              fontSize: screenSize.width * 0.045,
                              color: const Color(0xFF171A1F),
                            ),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: screenSize.width * 0.04,
                                vertical: fieldHeight * 0.25,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Color(0xFF636AE8),
                                  width: 1,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Color(0xFF636AE8),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Color(0xFF636AE8),
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 1,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                              errorStyle: TextStyle(
                                color: Colors.red,
                                fontSize: screenSize.width * 0.035,
                                height: 0.5,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: const Color(0xFF171A1F),
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
                        ),
                        SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // Removed error message from here - moved to end of Stack for proper layering

                  // Sign In Button - styled to match design
                  Positioned(
                    top: screenSize.height * 0.71,
                    left: screenSize.width * 0.06,
                    right: screenSize.width * 0.06,
                    child: SizedBox(
                      width: double.infinity,
                      height: fieldHeight,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF323483),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 1,
                        ),
                        child:
                            _isLoading
                                ? SizedBox(
                                  height: screenSize.width * 0.06,
                                  width: screenSize.width * 0.06,
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                                : Text(
                                  "Sign In",
                                  style: GoogleFonts.inter(
                                    fontSize: screenSize.width * 0.045,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFFFFFFF),
                                  ),
                                ),
                      ),
                    ),
                  ),

                  // Add bottom padding to ensure content is properly spaced from bottom edge
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: safeAreaBottom > 0 ? safeAreaBottom : 20,
                    ),
                  ),

                  // Error message display - positioned last to appear on top of other elements
                  if (_errorMessage.isNotEmpty)
                    Positioned(
                      top: screenSize.height * 0.67,
                      left: screenSize.width * 0.06,
                      right: screenSize.width * 0.06,
                      child: Material(
                        elevation: 6, // Add elevation to ensure it appears on top
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.transparent,
                        child: Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            minHeight: 50,
                            maxHeight: 150,
                          ),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(200), // Much higher opacity for better text readability
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.red.withAlpha(180),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(51), // 20% opacity
                                offset: Offset(0, 3),
                                blurRadius: 6,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.error_outline,
                                  color: Colors.white, // White icon for better contrast on red background
                                  size: screenSize.width * 0.05,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: Colors.white, // White text on red background for better contrast
                                    fontSize: screenSize.width * 0.038,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.visible,
                                  softWrap: true,
                                ),
                              ),
                              SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _errorMessage = '';
                                  });
                                },
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    color: Colors.white, // White close icon for better visibility
                                    size: screenSize.width * 0.045,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
