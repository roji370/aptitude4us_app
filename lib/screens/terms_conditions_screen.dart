import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Terms and Conditions'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome to Xfini Academy for Nurses. By accessing this platform and engaging with any of its educational content, you acknowledge and agree to the following legally binding terms. All material provided within this platform—including but not limited to videos, audio recordings, presentation slides, written documents, illustrations, and any supporting digital or printed media—is the exclusive intellectual property of Xfini Academy for Nurses and its contributors. These materials are protected under national and international copyright legislation, including the Copyright and Related Rights Act, 2000 of Ireland and The Copyright Act, 1957 (as amended) of India.\n\n"
                  "This educational content is provided strictly for personal learning and professional development. Any attempt to download, copy, reproduce, screen-record, distribute, transmit, alter, adapt, translate, publicly display, or upload any part of the content to third-party platforms or social networks constitutes an infringement of copyright law. Sharing materials in any form, including via email, messaging services, cloud storage, or learning forums, without explicit, prior written consent from Xfini Academy for Nurses is strictly prohibited.\n\n"
                  "Such unauthorised actions are considered serious offences and may result in immediate revocation of access to all resources and services offered by Xfini Academy for Nurses. Furthermore, violators may face civil and criminal liability. Under Section 140 to 146 of the Irish Copyright and Related Rights Act, 2000, and Sections 63 to 70 of the Indian Copyright Act, 1957, copyright infringement may lead to legal proceedings, substantial financial penalties, and, in certain cases, imprisonment.\n\n"
                  "By proceeding to access and use this platform, you confirm your understanding of and commitment to upholding these copyright conditions. You agree to respect the creative and intellectual efforts that underpin the development of these educational resources. If you are uncertain about any aspect of acceptable usage or if you wish to obtain permission for specific purposes, we urge you to contact Xfini Academy for Nurses directly at [insert contact email].\n\n"
                  "We thank you for your cooperation in safeguarding the integrity of our educational assets and for contributing to a culture of respect, responsibility, and legal compliance.",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF4D4D4D),
                    height: 1.6,
                  ),
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
