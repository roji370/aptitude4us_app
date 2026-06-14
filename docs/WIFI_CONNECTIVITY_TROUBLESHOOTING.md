# 🌐 WiFi Connectivity Troubleshooting Guide

## 📊 App Backend Configuration

### Your App Uses: Firebase Services (Google Cloud)

| Service | Domain | Port | SSL |
|---------|--------|------|-----|
| **Firebase Auth** | `identitytoolkit.googleapis.com` | 443 | ✅ |
| **Cloud Firestore** | `firestore.googleapis.com` | 443 | ✅ |
| **Cloud Functions** | `*.cloudfunctions.net` | 443 | ✅ |
| **Firebase Storage** | `course-c18bb.firebasestorage.app` | 443 | ✅ |
| **Firebase Messaging** | `fcm.googleapis.com` | 443 | ✅ |
| **Firebase Messaging (Ports)** | Various | 5228, 5229, 5230 | ✅ |

**Result**: Your backend is perfectly configured with industry best practices ✅

---

## 🔍 Root Cause Analysis

Since the backend is Firebase (top-tier infrastructure), WiFi issues are **network-level restrictions**, not app configuration problems.

### Why WiFi Fails But Mobile Data Works

| Network Type | Typical Restrictions | Result |
|-------------|---------------------|--------|
| **Mobile Data** | ❌ No firewall<br>❌ No content filtering<br>❌ No port blocking | ✅ App works |
| **Home WiFi** | ✅ Usually open<br>❌ Minimal restrictions | ✅ Usually works |
| **School WiFi** | 🔒 Firewall<br>🔒 Content filtering<br>🔒 Port blocking | ❌ Often blocked |
| **Office WiFi** | 🔒 Corporate firewall<br>🔒 SSL inspection<br>🔒 Whitelisting | ❌ Often blocked |
| **Public WiFi** | 🔒 Captive portal<br>🔒 Limited access | ⚠️ Requires login |

---

## 🎯 Most Common Causes

### 1. 🔴 Corporate/School Firewall Blocking Firebase

**Symptom:**
- Works on mobile data ✅
- Fails on school/office WiFi ❌
- Login specifically fails (timeout error)

**Why:**
Many institutional networks block:
- `*.googleapis.com` (all Google APIs)
- `*.cloudfunctions.net` (Cloud Functions)
- `*.firebaseio.com` (Realtime Database)
- Ports 5228-5230 (Firebase Cloud Messaging)

**Your app uses Cloud Functions for:**
- ✅ Login validation (`validateUserDevice`)
- ✅ Device registration (`registerUserDevice`)
- ✅ Content updates (`markUpdateAsSeen`)
- ✅ Screenshot monitoring (`recordScreenshotViolation`)

**If blocked** → Login fails, app unusable

**Solution:**
- **For Users**: Ask IT department to whitelist Firebase domains
- **For IT Admins**: Whitelist these domains:
  ```
  *.googleapis.com
  *.cloudfunctions.net
  *.firebasestorage.app
  *.firebaseio.com
  fcm.googleapis.com
  firebaseinstallations.googleapis.com
  ```
- **Ports to allow**: 443, 5228, 5229, 5230

---

### 2. 🟡 Captive Portal (Login Required)

**Symptom:**
- WiFi shows "connected" ✅
- Browser doesn't work either ❌
- No apps work until browser login ❌

**Why:**
Hotels, airports, cafes, malls require:
- Opening browser
- Accepting terms
- Sometimes entering email/room number

**Solution:**
1. Connect to WiFi
2. Open browser (any website)
3. Complete login/accept terms
4. Then open app

---

### 3. 🟡 DNS Resolution Issues

**Symptom:**
- Random WiFi networks fail ❌
- No pattern (sometimes works, sometimes doesn't)
- Other Google apps also slow/failing

**Why:**
- Router's DNS server can't resolve Firebase domains
- ISP DNS issues
- DNS cache corruption

**Solution for Users:**

**Android:**
1. Settings → Network & Internet → WiFi
2. Long press connected network
3. Modify network → Advanced options
4. IP settings → Static
5. DNS 1: `8.8.8.8` (Google)
6. DNS 2: `1.1.1.1` (Cloudflare)
7. Save and reconnect

**iOS:**
1. Settings → WiFi
2. Tap (i) next to connected network
3. Configure DNS → Manual
4. Remove existing DNS
5. Add: `8.8.8.8` and `1.1.1.1`
6. Save

---

### 4. 🟡 VPN/Proxy Interference

**Symptom:**
- Works without VPN ✅
- Fails with VPN ❌
- May work with different VPN server

**Why:**
- VPN blocking Google services
- VPN routing through restricted country
- Proxy misconfiguration

**Solution:**
- Disable VPN temporarily
- Try different VPN server/location
- Whitelist app in VPN settings
- Use VPN that doesn't block Google services

---

### 5. 🟢 SSL Inspection (Corporate Networks)

**Symptom:**
- Only on corporate/enterprise WiFi ❌
- Certificate errors in logs
- Other encrypted apps also fail

**Why:**
Corporate firewalls intercept SSL traffic for inspection. If certificates aren't properly handled, connection fails.

**Solution:**
- Install corporate SSL certificate on device
- Ask IT to exclude Firebase domains from inspection
- Use mobile data for sensitive operations

---

## 🧪 Diagnostic Tests for Users

### Test 1: Browser Check
```
Open browser, visit: https://firestore.googleapis.com
```

| Result | Meaning | Next Step |
|--------|---------|-----------|
| Loads (shows error page) ✅ | Firebase reachable | Check app-specific issues |
| Doesn't load / timeout ❌ | Network blocking Firebase | Contact IT or use mobile data |
| Redirects to login page | Captive portal | Complete WiFi login |

---

### Test 2: VPN Test
```
1. App fails on WiFi ❌
2. Enable VPN
3. Try app again
```

| Result | Meaning |
|--------|---------|
| Works with VPN ✅ | Network/ISP blocking Firebase |
| Still fails ❌ | App or device issue |

---

### Test 3: Mobile Hotspot Test
```
1. Enable mobile hotspot on another device
2. Connect to hotspot WiFi
3. Try app
```

| Result | Meaning |
|--------|---------|
| Works ✅ | Original WiFi network is blocking |
| Fails ❌ | Device or app issue |

---

### Test 4: Different WiFi Test
```
Try app on:
- Home WiFi
- Friend's WiFi
- Coffee shop WiFi
- School WiFi
```

| Pattern | Cause |
|---------|-------|
| Fails only on school/office | Institutional firewall |
| Fails on all WiFi | Device/app issue |
| Random failures | DNS or routing issues |

---

## 🛠️ Solutions by User Type

### 👨‍🎓 Students (School WiFi Blocked)

**Options:**
1. **Ask IT to whitelist** (best solution)
   - Show them this document
   - Explain it's educational app
   - Provide domain list

2. **Use mobile data for login**
   - Login with mobile data
   - Switch to WiFi after logged in
   - Most features will work except Cloud Functions

3. **Use personal hotspot**
   - Share connection from phone
   - Connect device to hotspot

4. **Use VPN**
   - Install VPN app
   - Connect to VPN
   - Then use app

---

### 💼 Office Workers (Corporate WiFi Blocked)

**Options:**
1. **Request IT whitelist**
   - Submit ticket with domain list
   - Explain it's work-related app
   - Provide this documentation

2. **Use mobile data**
   - More reliable
   - No firewall issues

3. **Install corporate certificate**
   - If SSL inspection is enabled
   - Contact IT for certificate

---

### 🏠 Home Users (General Issues)

**Try these steps:**

1. **Restart router**
   ```
   Unplug router → Wait 30 seconds → Plug back in
   ```

2. **Change DNS** (see instructions above)

3. **Update router firmware**
   - Check manufacturer website
   - Apply available updates

4. **Contact ISP**
   - If persistently blocked
   - Ask about Firebase/Google blocking

---

## 📱 App-Side Improvements

### What We've Done ✅

1. **Added network state permissions**
   ```xml
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
   <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
   ```
   - Helps app detect WiFi vs mobile data
   - Enables proper network handling
   - Allows Firebase SDK to adapt

2. **Proper error handling**
   - Better error messages
   - Timeout detection
   - Network failure handling

### What Users Can Do

**If connection fails:**
1. ✅ Check WiFi is connected
2. ✅ Try opening browser
3. ✅ Complete captive portal if present
4. ✅ Switch to mobile data
5. ✅ Try VPN
6. ✅ Contact network administrator

---

## 📊 Network Requirements (For IT Admins)

### Required Domains (Whitelist)
```
*.googleapis.com
*.cloudfunctions.net
*.firebasestorage.app
*.firebaseio.com
fcm.googleapis.com
firebaseinstallations.googleapis.com
identitytoolkit.googleapis.com
securetoken.googleapis.com
```

### Required Ports
```
Port 443 (HTTPS) - Critical
Port 5228 (FCM) - For notifications
Port 5229 (FCM) - For notifications  
Port 5230 (FCM) - For notifications
```

### Protocol Requirements
- ✅ HTTPS (TLS 1.2+)
- ✅ HTTP/2 support
- ✅ WebSocket support (for Firestore real-time)

### SSL/TLS
- Valid Google SSL certificates
- If SSL inspection enabled: Exclude Firebase domains or install proper intermediate certificates

---

## 🎯 Quick Reference

| Issue | Quick Fix |
|-------|-----------|
| **School/Office WiFi** | Contact IT → Whitelist Firebase |
| **Captive Portal** | Open browser → Complete login |
| **DNS Issues** | Change DNS to 8.8.8.8 |
| **VPN Blocking** | Disable VPN or change server |
| **SSL Errors** | Install corporate certificate |
| **No Solution** | Use mobile data |

---

## 📞 Support Response Template

When users report WiFi issues, send them this:

```
Thanks for reporting! This appears to be a network restriction issue, not an app bug.

Your app uses Firebase (Google Cloud), which is blocked by some WiFi networks.

Quick checks:
1. Can you open https://firestore.googleapis.com in your browser?
2. Does the app work on mobile data?
3. Are you on school/office WiFi?

Solutions:
✅ If school/office WiFi: Ask IT to whitelist Firebase domains
✅ Try mobile data: Should work immediately
✅ Try VPN: May bypass restrictions
✅ Captive portal: Complete WiFi login in browser first

See our troubleshooting guide: [Link to this doc]
```

---

## ✅ Summary

| Component | Status | Notes |
|-----------|--------|-------|
| **Backend (Firebase)** | ✅ Perfect | HTTPS, port 443, valid SSL |
| **App Permissions** | ✅ Fixed | Network state detection added |
| **Root Cause** | 🔒 Network Blocking | Institutional firewalls blocking Firebase |
| **User Solution** | ⚠️ Contact IT | Request domain whitelisting |
| **Workaround** | ✅ Mobile Data | Always works |

---

**Project**: Xfini Academy  
**Backend**: Firebase (course-c18bb)  
**Issue Type**: Network-level restriction  
**User Impact**: Medium (workarounds available)  
**Fix Date**: November 17, 2025  
**Status**: ✅ Documented & Permissions Added

