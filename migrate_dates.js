/**
 * Migration Script: Convert dateOfJoining and examDate from milliseconds to Firestore Timestamps
 * 
 * This script updates all user documents in Firestore where dateOfJoining and/or examDate
 * are stored as integers (milliseconds) and converts them to proper Firestore Timestamp objects.
 * 
 * Run this script once using: node migrate_dates.js
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
// Make sure you have your service account key file
const serviceAccount = require('./firebase-functions/serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function migrateDateFields() {
  try {
    console.log('Starting migration of date fields...');
    
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    console.log(`Found ${usersSnapshot.size} user documents`);
    
    let updatedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
    // Process each user document
    for (const doc of usersSnapshot.docs) {
      try {
        const data = doc.data();
        const updates = {};
        let needsUpdate = false;
        
        // Check dateOfJoining
        if (data.dateOfJoining !== undefined && data.dateOfJoining !== null) {
          if (typeof data.dateOfJoining === 'number') {
            // Convert milliseconds to Timestamp
            updates.dateOfJoining = admin.firestore.Timestamp.fromMillis(data.dateOfJoining);
            needsUpdate = true;
            console.log(`  User ${doc.id}: Converting dateOfJoining from ${data.dateOfJoining} to Timestamp`);
          }
        }
        
        // Check examDate
        if (data.examDate !== undefined && data.examDate !== null) {
          if (typeof data.examDate === 'number') {
            // Convert milliseconds to Timestamp
            updates.examDate = admin.firestore.Timestamp.fromMillis(data.examDate);
            needsUpdate = true;
            console.log(`  User ${doc.id}: Converting examDate from ${data.examDate} to Timestamp`);
          }
        }
        
        // Update the document if needed
        if (needsUpdate) {
          await doc.ref.update(updates);
          updatedCount++;
          console.log(`✅ Updated user ${doc.id}`);
        } else {
          skippedCount++;
          console.log(`⏭️  Skipped user ${doc.id} (already in correct format or no dates)`);
        }
        
      } catch (error) {
        errorCount++;
        console.error(`❌ Error processing user ${doc.id}:`, error);
      }
    }
    
    console.log('\n' + '='.repeat(50));
    console.log('Migration complete!');
    console.log(`✅ Updated: ${updatedCount} users`);
    console.log(`⏭️  Skipped: ${skippedCount} users`);
    console.log(`❌ Errors: ${errorCount} users`);
    console.log('='.repeat(50));
    
  } catch (error) {
    console.error('Fatal error during migration:', error);
  } finally {
    // Exit the script
    process.exit(0);
  }
}

// Run the migration
migrateDateFields();

