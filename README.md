# 🎥 VideoCall App - Complete Backend

FastAPI + MongoDB backend for a video calling app with admin panel.

> 📱 **Flutter mobile app:** [`flutter_app/`](flutter_app/) — complete app (auth, discover, calls, wallet, gifts, chatbot, levels) against this same API.

## 🚀 Quick Start

```bash
# 1. MongoDB chalao (localhost:27017)
# 2. Run karo:
bash start.sh

# Ya manually:
pip install -r requirements.txt
uvicorn main:app --reload
```

- **API Docs:** http://localhost:8000/docs
- **Admin Panel:** http://localhost:8000/admin-panel
- **Admin Login:** `.env` ke `ADMIN_USERNAME` / `ADMIN_PASSWORD` se (default creds kabhi production me mat chhodo)

> ⚠️ **Security:** `.env` git me commit mat karo. `.env.example` ko copy karke `.env` banao.
> Agar pehle se real credentials git history me leak ho chuke hain, toh **MongoDB password aur SECRET_KEY rotate karo**.

---

## 📋 All API Endpoints

### 🔐 AUTH — `/api/v1/auth`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | New user register (form-data: name, mobile, password, gender, profile_picture) |
| POST | `/auth/login` | Login (form-data: mobile, password) |
| POST | `/auth/guest-login` | Guest mode login |
| GET | `/auth/me` | Current user profile (Bearer token) |
| PUT | `/auth/profile` | Update profile |
| POST | `/auth/convert-guest` | Guest → Full account |

### 🏠 HOSTS/DISCOVER — `/api/v1/hosts`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/hosts/discover` | Home screen hosts (filters: interest, gender, level, sort_by, page) |
| GET | `/hosts/featured` | Featured hosts for banner |
| GET | `/hosts/online` | Currently online hosts |
| GET | `/hosts/{id}` | Single host detail |
| POST | `/hosts/admin/add` | Admin: Add host (form-data: profile pic, `images[]`, `videos[]`, preview/call video, description, city, rate, AI bot fields) |
| PUT | `/hosts/admin/{id}` | Admin: Update host (naye images/videos append hote hain; `clear_fields=a,b` se fields khali karo) |
| DELETE | `/hosts/admin/{id}/media` | Admin: Ek media hatao `?kind=image\|video\|call_video\|preview_video\|profile_picture&url=...` |
| DELETE | `/hosts/admin/{id}` | Admin: Delete host |
| GET | `/hosts/admin/list/all` | Admin: All hosts list |
| GET | `/hosts/admin/{id}` | Admin: Full host (bot personality/instructions ke saath) |

### 📹 VIDEO CALLS — `/api/v1/calls`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/calls/initiate` | Start call `{"host_id": "...", "call_type": "outgoing"\|"incoming"}` — **402** agar balance < 1 min; returns `call_video`, `connecting_seconds`, `billing_tick_seconds`, `host_message`. Outgoing pe host ka message turant user ke Inbox me (balance kam ho toh "recharge kar lo" wala) |
| POST | `/calls/answer/{call_id}` | Connecting khatam → call active, billing shuru |
| POST | `/calls/billing-check` | Har few sec (default 5s) — per-second deduction, returns `continue` / `low_balance` warning / `end_call` |
| POST | `/calls/end` | End call, add rating (unanswered = free) |
| GET | `/calls/random-host` | Incoming call ke liye random online host + `ring_timeout_seconds` |
| POST | `/calls/incoming/respond` | Incoming log `{"host_id": "...", "action": "rejected"\|"missed"}` |
| GET | `/calls/history` | User's call history |
| GET | `/calls/admin/all` | Admin: All calls |

#### 💡 Call Flow (outgoing + incoming same):
```
1. POST /calls/initiate        → call_id, call_video, connecting_seconds (default 10)
   (402 = balance kam → app recharge prompt dikhata hai)
2. App "Calling… / Connecting…" screen dikhata hai (connecting_seconds) — isme koi charge nahi
3. POST /calls/answer/{call_id} → host ka admin-uploaded video play hota hai, billing start
4. Har billing_tick_seconds → POST /calls/billing-check {"call_id": "..."}
   - Server-side per-second billing (rate/min ÷ 60), atomic debit — double charge impossible
   - ≤ 60 sec ka balance bacha → "low_balance": true (app banner + Recharge button)
   - Balance khatam → {"action": "end_call", "reason": "insufficient_balance"} → call auto-end,
     status ended_insufficient_balance, app "balance khatam" notice + recharge prompt
   - Heartbeat 45 sec tak nahi aaya → call timed_out (sirf utne time ka charge)
5. POST /calls/end {"call_id": "...", "rating": 5} → final settlement
```

#### 📲 Incoming calls
App open & use me ho toh har `incoming_call_interval_seconds` (default **300 = 5 min**, admin
panel se change) pe `GET /calls/random-host` → Incoming screen (Accept / Reject, 30s ring).
Accept → `initiate` with `call_type: "incoming"` → upar wala same flow (balance kam ho toh
recharge prompt). Reject/miss → `/calls/incoming/respond`.

#### 💬 Host message on Video Call button
User kisi host ko video call kare → backend us host ki taraf se user ke Inbox thread me message
daalta hai (unread +1). Text: host ka apna `call_message` (host modal) → warna global
`call_message` (Priya & Calls page). Placeholders `{user}` `{host}` `{price}`. Balance kam ho
toh `call_message_low_balance`. Same message 60 sec me dobara nahi (double-tap safe).

### ⚙️ APP SETTINGS — `/api/v1/settings`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/settings/app` | Public: connecting seconds, billing tick, incoming interval, Priya name |
| GET | `/settings/admin` | Admin: saari settings (Priya bot personality/instructions bhi) |
| PUT | `/settings/admin` | Admin: update (partial JSON) |

### 💰 WALLET — `/api/v1/wallet`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/wallet/balance` | Current balance |
| GET | `/wallet/packages` | Coin packages list |
| POST | `/wallet/recharge` | Create recharge request `{"amount": 199, "payment_method": "upi", "transaction_ref": "UPI-UTR"}` — status **pending**, coins only after admin approval |
| GET | `/wallet/my-recharges` | My recharge request statuses |
| GET | `/wallet/transactions` | Transaction history |
| POST | `/wallet/admin/credit` | Admin: Credit coins to user |
| GET | `/wallet/admin/all-transactions` | Admin: All transactions |
| GET | `/wallet/admin/recharges?status=pending` | Admin: Recharge requests (verify UPI payment) |
| POST | `/wallet/admin/recharges/{id}/approve` | Admin: Approve → coins credited |
| POST | `/wallet/admin/recharges/{id}/reject` | Admin: Reject with reason |

#### 💳 Recharge Flow (secure):
```
1. POST /wallet/recharge {"amount": 199} → request pending, app shows pay_to_upid
2. User pays to that UPI ID, transaction_ref (UTR) submit karta hai
3. Admin panel → Wallet → Pending Recharge Requests → verify → Approve
4. Coins credited atomically (double-approve impossible)
```

#### 💳 Coin Packages:
| Price | Coins | Bonus |
|-------|-------|-------|
| ₹49 | 50 | 0 |
| ₹89 | 100 | +10 |
| ₹199 | 250 | +30 |
| ₹379 | 500 | +75 |
| ₹699 | 1000 | +200 |
| ₹1299 | 2000 | +500 |

### 🎁 GIFTS — `/api/v1/gifts`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/gifts/list` | All available gifts |
| GET | `/gifts/categories` | Gifts grouped by category |
| POST | `/gifts/send` | Send gift `{"gift_id":"...", "host_id":"...", "call_id":"...", "message":"..."}` |
| GET | `/gifts/my-history` | My gift sending history |
| POST | `/gifts/admin/add` | Admin: Add new gift |
| PUT | `/gifts/admin/{id}` | Admin: Update gift |
| GET | `/gifts/admin/stats` | Admin: Gift statistics |

### 🤖 CHAT BOT & RANDOM MATCH — `/api/v1/chat`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/chat/inbox` | Inbox: saare chat-enabled hosts + last message + unread (recent chats upar) |
| GET | `/chat/bot/thread?host_id=` | Host ke saath latest chat thread (na ho toh naya) + persona; read mark karta hai |
| GET | `/chat/bot/persona?host_id=` | Persona info (Priya default ya kisi host ka) — name, avatar, greeting, call host |
| POST | `/chat/bot/message` | AI chat `{"message": "Heyy!", "conversation_id": null, "host_id": null}` — Hindi / English / Hinglish auto-detect |
| GET | `/chat/bot/history/{conv_id}` | Get chat history |
| GET | `/chat/bot/my-conversations` | All bot conversations |
| POST | `/chat/bot/new-session` | Fresh session `{"host_id": null}` → conversation_id + greeting |
| POST | `/chat/admin/bot-test` | Admin: bot ko test karo (save se pehle) |
| POST | `/chat/random-match` | Random match with host `{"interest": "Music"}` |
| GET | `/chat/random-match/interests` | Popular interests for filter |

### ⭐ LEVELS & XP — `/api/v1/levels`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/levels/my-level` | My current level, XP, perks |
| GET | `/levels/leaderboard` | Top users by XP |
| GET | `/levels/all-levels` | All level details |

### 👮 ADMIN — `/api/v1/admin`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/admin/login` | `{"username":"admin","password":"Admin@123"}` |
| GET | `/admin/dashboard` | Complete stats summary |
| GET | `/admin/users` | All users (search, filter, pagination) |
| GET | `/admin/users/{id}` | User detail with stats |
| POST | `/admin/users/block` | Block user |
| POST | `/admin/users/unblock/{id}` | Unblock user |
| DELETE | `/admin/users/{id}` | Delete user |
| GET | `/admin/analytics?days=30` | Analytics over time |
| POST | `/admin/notifications/send` | Send notification |
| GET | `/admin/notifications` | All notifications |

---

### 🤖 AI bot kaise kaam karta hai
- Persona = admin panel ki info: **Priya & Calls** page (default Priya) ya host modal ka "AI Chat" section
  (personality, interests, background, conversation style, instructions, greeting).
- User jis language me likhe (Hindi देवनागरी / English / Hinglish) usi me reply — last messages ka context bhi jaata hai.
- `AI_API_KEY` set ho toh koi bhi OpenAI-compatible LLM (`AI_BASE_URL`, `AI_MODEL`); warna built-in
  rule-based Hindi/English/Hinglish fallback (app kabhi break nahi hota).

---

## 🏗 XP Actions (Auto Level System)

| Action | XP Gained |
|--------|-----------|
| Video call karna | +10 XP |
| Gift bhejna | +15 XP |
| Bot se chat | +1 XP |
| Daily login | +5 XP |
| Profile complete | +50 XP |
| Call receive | +5 XP |
| Gift receive | +8 XP |

## 🎯 Levels

| Level | Title | XP Required |
|-------|-------|-------------|
| 1 | Newcomer 🌱 | 0 |
| 2 | Explorer 🗺️ | 100 |
| 3 | Regular ⭐ | 300 |
| 4 | Active 🔥 | 600 |
| 5 | Popular 💫 | 1000 |
| 6 | Star 🌟 | 1500 |
| 7 | Super Star 🏆 | 2200 |
| 8 | Legend 👑 | 3000 |
| 9 | Elite 💎 | 4000 |
| 10 | Champion 🎖️ | 5500 |

---

## 📁 Project Structure

```
videocall-app/
├── main.py                 # FastAPI app entry point
├── requirements.txt
├── .env                    # Config (MongoDB URL, secret key)
├── start.sh               # Quick start script
├── admin/
│   └── index.html         # Complete Admin Panel
├── static/
│   └── uploads/           # Media files
└── app/
    ├── core/
    │   ├── config.py      # Settings
    │   ├── database.py    # MongoDB connection
    │   └── security.py    # JWT auth
    ├── routers/
    │   ├── auth.py        # Login/Register
    │   ├── hosts.py       # Host users/Discover
    │   ├── calls.py       # Video calls + billing
    │   ├── wallet.py      # Wallet system
    │   ├── gifts.py       # Gift module
    │   ├── chat.py        # Bot + random match
    │   ├── admin.py       # Admin APIs
    │   └── levels.py      # XP/Levels
    └── utils/
        └── helpers.py     # Utilities
```

## ⚙️ Environment Variables (.env)

`.env.example` copy karke banao — `.env` git me commit mat karo:

```
MONGODB_URL=mongodb://localhost:27017
DATABASE_NAME=videocall_app
SECRET_KEY=your-secret-key-here-min-32-chars
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your-strong-admin-password
MAX_VIDEO_SIZE=104857600          # host videos (100 MB)

# AI chat (optional — khali = built-in fallback bot)
AI_API_KEY=
AI_BASE_URL=https://api.openai.com/v1
AI_MODEL=gpt-4o-mini
```

## 🔒 Security Notes

- `/api/v1/upid/*` — add/update sirf **admin**, get ke liye login zaroori
- Recharge coins sirf **admin approval** ke baad credit hote hain (UPI payment verify karke)
- Wallet deductions **atomic** hain (race-safe)
- Call billing **server-side time based** hai
