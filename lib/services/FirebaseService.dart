import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Firebaseservice {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;
  CollectionReference get users => _db.collection('users');

  Future<void> setUserData(Map<String, dynamic> data) =>
      users.doc(uid).set(data, SetOptions(merge: true));

  Future<Map<String, dynamic>?> getUserData() async {
    final doc = await users.doc(uid).get();
    return doc.data() as Map<String, dynamic>?;
  }

  // Updates a single preference inside the nested 'preferences' map
  Future<void> updateUserPreference(String userId, String key, dynamic value) async {
    try {
      print('🚀 FIREBASE ATTEMPT: Saving $key = $value for user $userId');
      await users.doc(userId).set({
        'preferences': {
          key: value,
        }
      }, SetOptions(merge: true));
      print('✅ FIREBASE SUCCESS: Successfully updated $key to $value');
    } catch (e) {
      print('❌ FIREBASE ERROR: Failed to update preference: $e');
    }
  }
}
