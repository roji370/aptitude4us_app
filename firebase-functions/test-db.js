const admin = require("firebase-admin");
const serviceAccount = require("../../serviceAccountKey.json"); // I need to know if there's a service account key or I'll just use the default application credentials if it's run via firebase functions:shell

async function run() {
  admin.initializeApp();
  const db = admin.firestore();
  const snapshot = await db.collection("contentUpdates").orderBy("timestamp", "desc").limit(5).get();
  snapshot.forEach((doc) => {
    console.log(doc.id, "=>", JSON.stringify(doc.data(), null, 2));
  });
}
run().catch(console.error);
