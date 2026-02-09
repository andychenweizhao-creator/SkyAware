import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Use the singleton instance for google_sign_in ^7.0.0
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Expose current user
  User? get currentUser => _auth.currentUser;

  // Stream for auth changes (useful for routing)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Helper method to save user to Firestore if they don't exist
  Future<void> _saveUserToFirestore(User user) async {
    final userDoc = _firestore.collection('users').doc(user.uid);

    try {
      final snapshot = await userDoc.get();
      if (!snapshot.exists) {
        await userDoc.set({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName ?? '',
          'photoURL': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          // Default preferences
          'preferences': {
            'notificationsEnabled': true,
            'isDarkMode': false,
            'measurementUnit': 'metric', // metric vs imperial
          },
        });
      } else {
        // Update last login time
        await userDoc.update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Error saving user to Firestore: $e");
    }
  }

  // Upload Profile Image
  Future<String?> uploadProfileImage(File image, String uid) async {
    try {
      // Validate file exists
      if (!await image.exists()) {
        print("Error: Image file does not exist at path: ${image.path}");
        return null;
      }

      final ref = _storage.ref().child('user_avatars').child('$uid.jpg');

      // Upload task
      final UploadTask uploadTask = ref.putFile(image);

      // Optional: Monitor progress
      // uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
      //   print('Progress: ${(snapshot.bytesTransferred / snapshot.totalBytes) * 100} %');
      // });

      await uploadTask;
      final url = await ref.getDownloadURL();
      print("Upload successful. Download URL: $url");
      return url;
    } on FirebaseException catch (e) {
      print("Firebase Storage Error: ${e.code} - ${e.message}");
      if (e.code == 'permission-denied') {
        print(
            "Warning: Permission denied. Please check your Firebase Storage Security Rules.");
      }
      return null;
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  // Sign In with Email & Password
  Future<User?> signIn(String email, String password) async {
    UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password
    );

    // Ensure user exists in Firestore
    if (result.user != null) {
      await _saveUserToFirestore(result.user!);
    }

    return result.user;
  }

  // Sign In with Google
  Future<User?> signInWithGoogle() async {
    try {
      // Initialize if needed, though usually handled by the plugin.
      // With google_sign_in 7.x, we use authenticate()
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      
      final GoogleSignInAuthentication googleAuth = await googleUser
          .authentication;
      
      // Note: accessToken is no longer available in GoogleSignInAuthentication in v7
      // We rely on idToken.
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: null, 
        idToken: googleAuth.idToken,
      );

      final UserCredential result = await _auth.signInWithCredential(
          credential);

      if (result.user != null) {
        await _saveUserToFirestore(result.user!);
      }

      return result.user;
    } catch (e) {
      print("Error signing in with Google: $e");
      return null;
    }
  }
   Future<User?> signInWithApple() async {
    if(!Platform.isIOS) return null;
    try {
      final rawNonce = generateNonce();
      final nonce = sha256ofString(rawNonce);
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      final userCredential = await _auth.signInWithCredential(oauthCredential);

      return userCredential.user;
    } catch (e) {
      print("Error signing in with Apple: $e");
      return null;
    }
  }
  static String generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }
  static String sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }


  // Sign Up with Email & Password
  Future<User?> signUp(String email, String password,
      {String? displayName, File? profileImage}) async {
    UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);

    if (result.user != null) {
      String? photoURL;

      // Upload image if provided
      if (profileImage != null) {
        photoURL = await uploadProfileImage(profileImage, result.user!.uid);
        if (photoURL != null) {
          await result.user!.updatePhotoURL(photoURL);
        }
      }

      // Update display name if provided
      if (displayName != null && displayName.isNotEmpty) {
        await result.user!.updateDisplayName(displayName);
      }

      // Refresh the user to get the updated profile locally
      await result.user!.reload();

      // Get the updated user object
      User? updatedUser = _auth.currentUser;
      if (updatedUser != null) {
        try {
          // Manually update firestore with the new data
          final userDoc = _firestore.collection('users').doc(updatedUser.uid);
          await userDoc.set({
            'uid': updatedUser.uid,
            'email': updatedUser.email,
            'displayName': updatedUser.displayName ?? '',
            'photoURL': updatedUser.photoURL ?? '', // Save the photo URL
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'preferences': {
              'notificationsEnabled': true,
              'isDarkMode': false,
              'measurementUnit': 'metric',
            },
          });
        } catch (e) {
          print("Error saving user to Firestore during sign up: $e");
          // Fail gracefully if Firestore rules prevent writing,
          // allowing the user to still sign in since the Auth account was created.
        }
      }
    }

    return result.user;
  }

  // Sign Out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _googleSignIn.disconnect();
    await _auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    }
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found for that email.';
      case 'invalid-email':
        return 'Please enter a valid email.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
