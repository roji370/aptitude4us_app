import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final bool isFromSettings;

  const OnboardingScreen({super.key, this.isFromSettings = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _numPages = 2; // Welcome page + Terms page
  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();

    // Force immediate UI build for iOS cold start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild to ensure UI appears immediately
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // If from settings, show only the terms and conditions text
    if (widget.isFromSettings) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Terms and Conditions'),
          backgroundColor: const Color(0xFF323483),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildTermsContent(screenSize),
          ),
        ),
      );
    }

    // Regular onboarding experience
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Page view for onboarding slides
            PageView(
              controller: _pageController,
              physics:
                  _currentPage == 1 && !_termsAccepted
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
              onPageChanged: (int page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                // Welcome page
                _buildWelcomePage(screenSize),

                // Terms and conditions page
                _buildTermsPage(screenSize),
              ],
            ),

            // Bottom navigation
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x1A000000),
                      blurRadius: 5,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Page indicator dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _numPages,
                        (index) => _buildDot(index),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back button (if not on first page)
                        _currentPage > 0
                            ? TextButton(
                              onPressed: () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              child: const Text(
                                "Back",
                                style: TextStyle(
                                  color: Color(0xFF323483),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                            : const SizedBox(
                              width: 80,
                            ), // Empty space if on first page
                        // Continue/Get Started button
                        ElevatedButton(
                          onPressed:
                              _currentPage == _numPages - 1
                                  ? _termsAccepted
                                      ? _completeOnboarding
                                      : null
                                  : () {
                                    _pageController.nextPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF323483),
                            disabledBackgroundColor: Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _currentPage == _numPages - 1
                                ? "Get Started"
                                : "Continue",
                            style: TextStyle(
                              color:
                                  _currentPage == _numPages - 1 &&
                                          !_termsAccepted
                                      ? Colors.grey.shade500
                                      : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(Size screenSize) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App icon or logo
          Container(
            height: screenSize.width * 0.5,
            width: screenSize.width * 0.5,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/logo/app_logo.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Welcome text
          Text(
            "Welcome to Briffini Academy",
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF323483),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // App description
          Text(
            "Your trusted learning companion for nursing students studying abroad.",
            style: GoogleFonts.inter(
              fontSize: 16,
              color: const Color(0xFF757575),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTermsPage(Size screenSize) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        24,
        24,
        24,
        100,
      ), // Extra bottom padding for buttons
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Terms and Conditions",
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF323483),
            ),
          ),
          const SizedBox(height: 16),

          // Scrollable terms content
          Expanded(child: _buildTermsContent(screenSize)),

          // Accept checkbox
          if (!widget.isFromSettings)
            Row(
              children: [
                Checkbox(
                  value: _termsAccepted,
                  activeColor: const Color(0xFF323483),
                  onChanged: (value) {
                    setState(() {
                      _termsAccepted = value ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    "I have read and accept the Terms and Conditions",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTermsContent(Size screenSize) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Welcome to Briffini Academy for Nurses. By accessing this platform and engaging with any of its educational content, you acknowledge and agree to the following legally binding terms. All material provided within this platform—including but not limited to videos, audio recordings, presentation slides, written documents, illustrations, and any supporting digital or printed media—is the exclusive intellectual property of Briffini Academy for Nurses and its contributors. These materials are protected under national and international copyright legislation, including the Copyright and Related Rights Act, 2000 of Ireland and The Copyright Act, 1957 (as amended) of India.\n\n"
            "This educational content is provided strictly for personal learning and professional development. Any attempt to download, copy, reproduce, screen-record, distribute, transmit, alter, adapt, translate, publicly display, or upload any part of the content to third-party platforms or social networks constitutes an infringement of copyright law. Sharing materials in any form, including via email, messaging services, cloud storage, or learning forums, without explicit, prior written consent from Briffini Academy for Nurses is strictly prohibited.\n\n"
            "Such unauthorised actions are considered serious offences and may result in immediate revocation of access to all resources and services offered by Briffini Academy for Nurses. Furthermore, violators may face civil and criminal liability. Under Section 140 to 146 of the Irish Copyright and Related Rights Act, 2000, and Sections 63 to 70 of the Indian Copyright Act, 1957, copyright infringement may lead to legal proceedings, substantial financial penalties, and, in certain cases, imprisonment.\n\n"
            "By proceeding to access and use this platform, you confirm your understanding of and commitment to upholding these copyright conditions. You agree to respect the creative and intellectual efforts that underpin the development of these educational resources. If you are uncertain about any aspect of acceptable usage or if you wish to obtain permission for specific purposes, we urge you to contact Briffini Academy for Nurses directly at [insert contact email].\n\n"
            "We thank you for your cooperation in safeguarding the integrity of our educational assets and for contributing to a culture of respect, responsibility, and legal compliance.",
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF4D4D4D),
              height: 1.6,
            ),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color:
            _currentPage == index
                ? const Color(0xFF323483)
                : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    // Save that onboarding is complete and the terms version
    if (!widget.isFromSettings) {
      await prefs.setBool('onboarding_complete', true);
      await prefs.setInt('terms_version', 1); // Set current terms version

      // Navigate to login screen safely with mounted check
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }
}
