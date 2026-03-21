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

  // Saves an airport search to the user's recent_airports history
  Future<void> saveAirportSearch(String icaoCode) async {
    try {
      if (_auth.currentUser == null) {
        print('⚠️ FIREBASE WARNING: No authenticated user. Cannot save airport search.');
        return;
      }
      
      print('🚀 FIREBASE ATTEMPT: Saving $icaoCode to search history for user $uid');
      await users.doc(uid).set({
        'recent_airports': FieldValue.arrayUnion([icaoCode.toUpperCase()]),
      }, SetOptions(merge: true));
      print('✅ FIREBASE SUCCESS: Successfully added $icaoCode to recent_airports');
    } catch (e) {
      print('❌ FIREBASE ERROR: Failed to save airport search: $e');
    }
  }

  // Saves an imported flight route to the user's subcollection
  Future<void> saveImportedRoute(
      String origin, 
      String destination, 
      String routeString, 
      List<Map<String, dynamic>> waypoints) async {
    try {
      if (_auth.currentUser == null || _auth.currentUser!.isAnonymous) {
        print('⚠️ FIREBASE WARNING: No authenticated user. Cannot save route.');
        return;
      }
      
      final collectionRef = users.doc(uid).collection('imported_routes');
      
      // 1. Check if this exact route already exists
      final existingQuery = await collectionRef
          .where('route_string', isEqualTo: routeString)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        print('🔄 FIREBASE: Route already exists. Updating timestamp to bump to top.');
        // 2. If it exists, update the timestamp so it jumps to the top of the list!
        await existingQuery.docs.first.reference.update({
          'imported_at': FieldValue.serverTimestamp(),
        });
        return;
      }

      print('🚀 FIREBASE ATTEMPT: Saving full route $origin to $destination for user $uid');
      
      // 3. If it doesn't exist, create a new document
      await collectionRef.add({
        'origin': origin.toUpperCase(),
        'destination': destination.toUpperCase(),
        'route_string': routeString,
        'waypoints': waypoints, 
        'imported_at': FieldValue.serverTimestamp(),
      });
      
      print('✅ FIREBASE SUCCESS: Successfully saved full route with ${waypoints.length} waypoints');
    } catch (e) {
      print('❌ FIREBASE ERROR: Failed to save route: $e');
    }
  }

  // Batch deletes selected routes from the user's history
  Future<void> deleteSavedRoutes(List<String> documentIds) async {
    try {
      if (_auth.currentUser == null) return;
      
      final collectionRef = users.doc(uid).collection('imported_routes');
      final batch = _db.batch();
      
      for (String docId in documentIds) {
        batch.delete(collectionRef.doc(docId));
      }
      
      await batch.commit();
      print('✅ FIREBASE SUCCESS: Deleted ${documentIds.length} routes.');
    } catch (e) {
      print('❌ FIREBASE ERROR: Failed to delete routes: $e');
    }
  }

  // Removes specific airport searches from the history array
  Future<void> removeSelectedSearches(List<String> icaos) async {
    try {
      if (_auth.currentUser == null) return;
      await users.doc(uid).update({
        'recent_airports': FieldValue.arrayRemove(icaos),
      });
      print('✅ FIREBASE SUCCESS: Removed ${icaos.length} searches.');
    } catch (e) {
      print('❌ FIREBASE ERROR: Failed to remove searches: $e');
    }
  }

  // Clears the entire airport search history array
  Future<void> clearAllAirportSearches() async {
    try {
      if (_auth.currentUser == null) return;
      await users.doc(uid).update({
        'recent_airports': FieldValue.delete(), // Deletes the field entirely
      });
      print('✅ FIREBASE SUCCESS: Cleared all recent searches.');
    } catch (e) {
      print('❌ FIREBASE ERROR: Failed to clear searches: $e');
    }
  }
}
