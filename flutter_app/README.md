# 📱 VideoCall App — Flutter Client

Complete Flutter app for the FastAPI backend (`../main.py`). Saare backend endpoints covered.

## ✨ Features (backend ke saath mapped)

| Screen | Backend endpoints |
|--------|-------------------|
| Splash + auto-login | `GET /auth/me` |
| Login / Register / Guest | `POST /auth/login`, `/auth/register` (form-data + photo), `/auth/guest-login` |
| Discover (featured + filters + pagination) | `GET /hosts/discover`, `/hosts/featured`, `/chat/random-match/interests` |
| Host detail (preview video) | `GET /hosts/{id}` |
| **Video call (simulated)** | `/calls/initiate` → `/calls/answer` → **`/calls/billing-check` har 60 sec** → `/calls/end` (+rating) |
| Random match + incoming call | `POST /chat/random-match`, `GET /calls/random-host` |
| Wallet + UPI recharge | `GET /wallet/packages`, `POST /wallet/recharge` (**pending → admin approve**), `GET /upid/get` |
| Gifts (in-call bhi) | `GET /gifts/categories`, `POST /gifts/send` |
| Priya chatbot | `POST /chat/bot/message`, `/new-session`, `/history/{id}` |
| Levels + leaderboard | `GET /levels/my-level`, `/levels/leaderboard` |
| Profile / history / guest→full | `PUT /auth/profile`, `GET /calls/history`, `POST /auth/convert-guest` |

## 🚀 Setup

```bash
# 1. Flutter SDK (3.0+) install karo, phir is folder me:
flutter create . --platforms android,ios   # platform folders generate karega
flutter pub get

# 2. Backend ka URL set karo
#    lib/config/app_config.dart → baseUrl:
#    Android emulator: http://10.0.2.2:8000
#    Real device:      http://<PC-ka-LAN-IP>:8000  (donon same WiFi pe)

# 3. Backend chalao (repo root pe)
bash ../start.sh      # ya: uvicorn main:app --host 0.0.0.0 --port 8000

# 4. Run!
flutter run
```

## ⚙️ Android-specific

`android/app/src/main/AndroidManifest.xml` me add karo:

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- local http testing ke liye -->
    <application android:usesCleartextTraffic="true" ...>
```

## 📁 Structure

```
lib/
├── main.dart               # MultiProvider wiring + 401 → login redirect
├── config/app_config.dart  # baseUrl + billing interval
├── theme/app_theme.dart    # Dark brand theme
├── models/models.dart      # Host, Gift, CoinPackage, Txn, Recharge, CallLog, ChatMsg
├── services/api_service.dart  # JWT + form/JSON/multipart + FastAPI error parsing
├── providers/              # auth, host, wallet, call, gift, chat, level
└── screens/
    ├── splash_screen.dart
    ├── auth/               # login, register, convert_guest
    ├── home/               # main_shell, discover, host_detail
    ├── call/               # call_screen (billing loop), random_match, incoming_call
    ├── wallet/             # wallet + UPI recharge sheet
    ├── gifts/              # gift bottom sheet
    ├── chat/               # Priya bot chat
    ├── profile/            # profile, edit, call history
    └── levels/             # leaderboard
```

## 💡 Notes

- **Simulated calls:** backend me real WebRTC nahi hai — call screen host ki preview video loop karta hai, billing bilkul real hai (server-side time enforced, reconnect pe bhi settle).
- **Recharge = approval flow:** user UPI pe pay karta hai → request `pending` → admin panel (😎 `/admin-panel`) se approve → coins credit. App me "My Recharge Requests" me live status.
- Guests ko Call/Gift/Wallet buttons pe upgrade sheet dikhti hai (`convert-guest`).
- Balance har screen pe live — gift/call/billing sab `AuthProvider.updateBalance` se sync hote hain.
