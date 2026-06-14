# Student Learning App

A secure Flutter application for student learning with Firebase integration.

## Features

- **User Authentication**: Secure login system for students
- **Course Management**: Browse and access assigned courses
- **Module System**: Organized learning modules within each course
- **Content Viewing**: Support for various content types (video, PDF, text)
- **Responsive Design**: Works on mobile, tablet, and web platforms
- **Offline Mode**: Demo mode for testing without Firebase connection

## Technologies Used

- Flutter (UI Framework)
- Firebase Authentication
- Firestore Database
- Firebase Storage
- Provider (State Management)

## Getting Started

### Prerequisites

- Flutter SDK (version 3.x or higher)
- Android Studio or VS Code with Flutter extensions
- Firebase account (optional for Demo mode)

### Setup

1. Clone the repository:
   ```
   git clone [repository-url]
   ```

2. Install dependencies:
   ```
   flutter pub get
   ```

3. Run the app:
   ```
   flutter run
   ```

### Firebase Configuration

For full functionality (beyond demo mode):

1. Create a Firebase project in the Firebase Console
2. Enable Authentication, Firestore, and Storage
3. Update the Firebase options in `lib/main.dart` with your project credentials
4. Deploy Firestore security rules from `firestore.rules`
5. Deploy Storage security rules from `storage.rules`

## Usage

### Login

The app starts with a login screen. In demo mode, you can use any email and password.

### Course Navigation

After login, you'll see your assigned courses. Select a course to view its modules.

### Content Viewing

Select a module to access its content. The app supports:
- Video playback
- PDF viewing
- Text/HTML content

## Troubleshooting

- **Device Connection Issues**: Make sure USB debugging is enabled if using a physical device
- **Firebase Errors**: Check Firebase initialization in main.dart 
- **Content Loading Errors**: Verify network connection or try demo mode

## License

This project is licensed under the MIT License - see the LICENSE file for details.
