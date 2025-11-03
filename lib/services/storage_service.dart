import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/logger.dart';
import '../main.dart'; // For FirebaseInitHelper

class StorageService {
  // Flags to indicate operational mode
  bool _isStorageAvailable =
      true; // Default to true and check during initialization

  // Firebase Storage instance with error handling
  FirebaseStorage? _storage;
  bool _isInitializing = false;
  bool _hasInitialized = false;

  StorageService() {
    _initializeStorage();
  }

  Future<void> _initializeStorage() async {
    // Prevent multiple initialization attempts
    if (_hasInitialized || _isInitializing) {
      return;
    }
    
    _isInitializing = true;
    
    try {
      // Wait for Firebase to be initialized first
      await FirebaseInitHelper.ensureInitialized();

      _storage = FirebaseStorage.instance;
      _isStorageAvailable = true;
      _hasInitialized = true;
      Logger.i("Firebase Storage initialized successfully");
    } catch (e) {
      Logger.e("Failed to initialize Firebase Storage: $e");
      _isStorageAvailable = false;
      _storage = null;
    } finally {
      _isInitializing = false;
    }
  }

  // Get download URL for a file
  Future<String?> getDownloadURL(String path) async {
    if (!_isStorageAvailable || _storage == null) {
      Logger.w("Firebase Storage not available - returning null URL");
      return null;
    }

    try {
      return await _storage!.ref(path).getDownloadURL();
    } catch (e) {
      Logger.e("Error getting download URL: $e");
      return null;
    }
  }

  // Get list of files in a directory
  Future<List<String>> listFiles(String path) async {
    if (!_isStorageAvailable || _storage == null) {
      return [];
    }

    try {
      ListResult result = await _storage!.ref(path).listAll();
      return result.items.map((item) => item.fullPath).toList();
    } catch (e) {
      Logger.e("Error listing files: $e");
      return [];
    }
  }

  // Secure URL retrieval for PDFs
  Future<String> getSecurePdfUrl(String storagePath) async {
    if (!_isStorageAvailable || _storage == null) {
      throw Exception("Storage service is not available");
    }

    try {
      Logger.i("Getting secure PDF URL for path: $storagePath");

      // Handle different URL formats
      String path = storagePath;

      // If it's already a full URL, extract the path
      if (storagePath.startsWith('http')) {
        Logger.d("Converting HTTP URL to storage path");
        Uri uri = Uri.parse(storagePath);
        String fullPath = uri.path;

        // Extract the path after /o/
        int startIndex = fullPath.indexOf('/o/');
        if (startIndex >= 0) {
          path = Uri.decodeComponent(fullPath.substring(startIndex + 3));
          Logger.d("Extracted path from URL: $path");
        } else {
          Logger.w("Warning: Could not extract path from URL, using as-is");
        }
      } else if (storagePath.startsWith('gs://')) {
        // Remove gs://bucket-name/ prefix
        Logger.d("Converting gs:// URL to storage path");
        path = storagePath.replaceFirst(RegExp(r'gs://[^/]+/'), '');
        Logger.d("Extracted path from gs:// URL: $path");
      }

      // Create a reference to the file
      final ref = _storage!.ref().child(path);

      // Try to get metadata first to verify the file exists and user has access
      try {
        final metadata = await ref.getMetadata();
        Logger.d(
          "File exists with size: ${metadata.size}, contentType: ${metadata.contentType}",
        );
      } catch (e) {
        if (e is FirebaseException) {
          if (e.code == 'unauthorized' || e.code == 'permission-denied') {
            Logger.w("Permission denied when checking metadata: ${e.message}");
            throw Exception(
              "Access denied (403): You don't have permission to access this file. Please verify your course access.",
            );
          } else if (e.code == 'object-not-found') {
            Logger.w("File not found: ${e.message}");
            throw Exception(
              "File not found (404): The requested PDF file doesn't exist",
            );
          }
        }
        Logger.w("Warning: Could not get metadata: $e");
      }

      // Create a signed URL that expires in 1 hour
      try {
        final signedUrl = await ref.getDownloadURL();
        Logger.i("Generated secure PDF URL successfully");
        return signedUrl;
      } catch (e) {
        if (e is FirebaseException) {
          if (e.code == 'unauthorized' || e.code == 'permission-denied') {
            Logger.w(
              "Permission denied when getting download URL: ${e.message}",
            );
            throw Exception(
              "Access denied (403): You don't have permission to access this file. Please verify your course access.",
            );
          } else if (e.code == 'object-not-found') {
            Logger.w("File not found: ${e.message}");
            throw Exception(
              "File not found (404): The requested PDF file doesn't exist",
            );
          } else {
            Logger.e("Firebase error: ${e.code} - ${e.message}");
            throw Exception("Error accessing file: ${e.message}");
          }
        }
        Logger.e("Unknown error: $e");
        rethrow;
      }
    } catch (e) {
      Logger.e("Error getting secure PDF URL: $e");
      Logger.e("Stack trace: ${StackTrace.current}");
      rethrow;
    }
  }

  // Method to get more security details about file (for tracking)
  Future<Map<String, dynamic>> getFileMetadata(String storagePath) async {
    if (!_isStorageAvailable || _storage == null) {
      return {'available': false, 'error': 'Storage service unavailable'};
    }

    try {
      final ref = _storage!.ref().child(storagePath);
      final metadata = await ref.getMetadata();

      return {
        'name': metadata.name,
        'size': metadata.size,
        'contentType': metadata.contentType,
        'fullPath': metadata.fullPath,
        'updated': metadata.updated?.toIso8601String(),
        'md5Hash': metadata.md5Hash,
      };
    } catch (e) {
      Logger.e("Error getting file metadata: $e");
      return {'available': false, 'error': e.toString()};
    }
  }

  /// Upload profile photo to Firebase Storage
  /// Returns the download URL of the uploaded photo
  Future<String> uploadProfilePhoto(String userId, File imageFile) async {
    // Ensure storage is initialized before attempting upload
    await _initializeStorage();
    
    if (!_isStorageAvailable || _storage == null) {
      Logger.e("Firebase Storage is not available");
      throw Exception("Firebase Storage is not available");
    }

    try {
      Logger.i("Starting profile photo upload for user: $userId");
      
      // Verify file exists
      if (!await imageFile.exists()) {
        Logger.e("Image file does not exist: ${imageFile.path}");
        throw Exception("Selected image file not found");
      }
      
      // Get file size
      final fileSize = await imageFile.length();
      Logger.i("Image file size: ${fileSize} bytes");
      
      if (fileSize == 0) {
        Logger.e("Image file is empty");
        throw Exception("Selected image file is empty");
      }

      // Create a reference to the file location
      // IMPORTANT: Path must match storage rules: users/{userId}/profile/{filename}
      final String fileName = 'profile.jpg'; // Use simple name, overwrite each time
      final String storagePath = 'users/$userId/profile/$fileName';
      
      Logger.i("Upload path: $storagePath");
      
      final ref = _storage!.ref().child(storagePath);

      // Set metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': userId,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      Logger.i("Starting upload task...");
      
      // Upload the file
      final uploadTask = ref.putFile(imageFile, metadata);
      
      // Monitor upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        Logger.i('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });

      // Wait for upload to complete
      final snapshot = await uploadTask;
      
      Logger.i("Upload complete, getting download URL...");

      // Get the download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();

      Logger.i("Profile photo uploaded successfully: $downloadUrl");
      return downloadUrl;
    } on FirebaseException catch (e) {
      Logger.e("Firebase error uploading profile photo: ${e.code} - ${e.message}");
      if (e.code == 'unauthorized') {
        throw Exception("Permission denied. Please try logging out and back in.");
      } else if (e.code == 'storage/unauthorized') {
        throw Exception("Storage permission denied. Please contact support.");
      } else if (e.code == 'storage/unauthenticated') {
        throw Exception("Not authenticated. Please log in again.");
      } else {
        throw Exception("Upload failed: ${e.message ?? e.code}");
      }
    } catch (e) {
      Logger.e("Unexpected error uploading profile photo: $e");
      throw Exception("Failed to upload photo. Please try again.");
    }
  }
}
