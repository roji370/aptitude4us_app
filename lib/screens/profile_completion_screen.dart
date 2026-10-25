import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';
import 'main_screen.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();

  File? _selectedImage;
  String? _existingPhotoUrl;
  DateTime? _dateOfJoining;
  DateTime? _examDate;
  String? _subscriptionPeriod;

  bool _isLoading = false;
  bool _isUploadingImage = false;
  bool _isEditMode = false;
  bool _dataLoaded = false;

  final List<String> _subscriptionPeriods = [
    '16 Days',
    '1 Month',
    '2 Months',
    '3 Months',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userData = await authService.getUserData();

      if (userData != null && mounted) {
        setState(() {
          _isEditMode = userData.isProfileComplete;
          _existingPhotoUrl = userData.photoUrl;
          _dateOfJoining = userData.dateOfJoining;
          _examDate = userData.examDate;
          _subscriptionPeriod = userData.subscriptionPeriod;
          if (userData.mobile != null) {
            _mobileController.text = userData.mobile!;
          }
          _dataLoaded = true;
        });
      } else if (mounted) {
        setState(() {
          _dataLoaded = true;
        });
      }
    } catch (e) {
      Logger.e('Error loading existing profile: $e');
      if (mounted) {
        setState(() {
          _dataLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      // image_picker uses the system photo picker which handles permissions internally
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      Logger.e('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to pick image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isJoiningDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: isJoiningDate ? DateTime(2020) : DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isJoiningDate) {
          _dateOfJoining = picked;
        } else {
          _examDate = picked;
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if photo is provided (either new or existing)
    if (_selectedImage == null && _existingPhotoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a profile photo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_dateOfJoining == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select date of joining'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_examDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select exam date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_subscriptionPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select subscription period'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isUploadingImage = _selectedImage != null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final storageService = Provider.of<StorageService>(context, listen: false);
      final userId = authService.currentUser?.uid;

      if (userId == null) {
        throw Exception('User not logged in');
      }

      String photoUrl;
      
      // Upload new photo if selected, otherwise use existing
      if (_selectedImage != null) {
        Logger.i('Uploading profile photo...');
        try {
          photoUrl = await storageService.uploadProfilePhoto(
            userId,
            _selectedImage!,
          );
          Logger.i('Profile photo uploaded: $photoUrl');
        } catch (uploadError) {
          Logger.e('Failed to upload photo: $uploadError');
          throw Exception('Failed to upload photo. Please check your internet connection and try again.');
        }
      } else {
        photoUrl = _existingPhotoUrl!;
        Logger.i('Using existing photo URL');
      }

      setState(() {
        _isUploadingImage = false;
      });

      // Update user profile
      Logger.i('Updating user profile...');
      try {
        await authService.updateUserProfile(
          photoUrl: photoUrl,
          dateOfJoining: _dateOfJoining,
          examDate: _examDate,
          mobile: _mobileController.text.trim(),
          subscriptionPeriod: _subscriptionPeriod,
        );
      } catch (updateError) {
        Logger.e('Failed to update profile in Firestore: $updateError');
        throw Exception('Failed to save profile details. Please check your internet connection and try again.');
      }

      Logger.i('Profile ${_isEditMode ? "updated" : "completed"} successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile ${_isEditMode ? "updated" : "completed"} successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate based on mode
        if (_isEditMode) {
          // If editing, just pop back to settings
          Navigator.of(context).pop();
        } else {
          // If initial setup, navigate to home
          AppNavigator.pushAndRemoveUntil(
            context: context,
            page: const MainScreen(),
            predicate: (route) => false,
          );
        }
      }
    } on Exception catch (e) {
      // Handle our custom exceptions with user-friendly messages
      Logger.e('Error saving profile: $e');
      if (mounted) {
        String errorMessage = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // Handle any other unexpected errors
      Logger.e('Unexpected error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred. Please try again later.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isUploadingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary,
              AppColors.primaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button for edit mode
                  if (_isEditMode)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                  // Header
                  Text(
                    _isEditMode ? 'Edit Profile' : 'Complete Your Profile',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isEditMode 
                        ? 'Update your profile information'
                        : 'Please fill in your details to continue',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Profile Photo Section
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _isLoading ? null : _pickImage,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: _selectedImage != null
                                ? ClipOval(
                                    child: Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          _existingPhotoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.add_a_photo,
                                              size: 50,
                                              color: AppColors.primary,
                                            );
                                          },
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_a_photo,
                                        size: 50,
                                        color: AppColors.primary,
                                      ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap to add photo',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Form Fields Container
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mobile Number
                        _buildLabel('Mobile Number'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          enabled: !_isLoading,
                          decoration: _buildInputDecoration(
                            'Enter your mobile number',
                            Icons.phone,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Mobile number is required';
                            }
                            if (value.trim().length < 10) {
                              return 'Please enter a valid mobile number';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        // Date of Joining
                        _buildLabel('Date of Joining'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _isLoading
                              ? null
                              : () => _selectDate(context, true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _dateOfJoining != null
                                      ? DateFormat('dd MMM yyyy')
                                          .format(_dateOfJoining!)
                                      : 'Select date',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _dateOfJoining != null
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Exam Date
                        _buildLabel('Exam Date'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _isLoading
                              ? null
                              : () => _selectDate(context, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _examDate != null
                                      ? DateFormat('dd MMM yyyy')
                                          .format(_examDate!)
                                      : 'Select exam date',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _examDate != null
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Subscription Period
                        _buildLabel('Subscription Period'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _subscriptionPeriod,
                          decoration: _buildInputDecoration(
                            'Select subscription period',
                            Icons.access_time,
                          ),
                          isExpanded: true,
                          items: _subscriptionPeriods.map((period) {
                            return DropdownMenuItem(
                              value: period,
                              child: Text(period),
                            );
                          }).toList(),
                          onChanged: _isLoading
                              ? null
                              : (value) {
                                  setState(() {
                                    _subscriptionPeriod = value;
                                  });
                                },
                          validator: (value) {
                            if (value == null) {
                              return 'Please select subscription period';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isUploadingImage
                                      ? 'Uploading photo...'
                                      : 'Saving profile...',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _isEditMode ? 'Update Profile' : 'Complete Profile',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info text (only show for initial completion)
                  if (!_isEditMode)
                    Center(
                      child: Text(
                        'You need to complete your profile to access the app',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
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

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

