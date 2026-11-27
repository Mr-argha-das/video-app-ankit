# 🎥 VideoCall App — Backend Audit (READ-ONLY)

Yeh file sirf **documentation/audit** hai. Isme koi code change nahi kiya gaya. Saara content backend code (`app/`, `main.py`, `start.sh`, `.env.example`, `admin/index.html`, `flutter_app/`) se nikala hai.

---

## 1. Tech Stack, Folder Structure, Run/Deploy, .env Variables

### Tech Stack
| Layer | Tech |
|-------|------|
| Language | Python 3.11 |
| Web Framework | FastAPI 0.111.0 |
| ASGI Server | uvicorn 0.29.0 |
| Database | MongoDB (motor 3.4.0 async driver) |
| Auth | python-jose (JWT HS256) + bcrypt |
| HTTP client (AI) | httpx 0.27.0 |
| File uploads | python-multipart, aiofiles |
| Admin panel | Static HTML/JS (`admin/index.html`, served by FastAPI) |
| Client | Flutter (see section 10) |

### Folder Structure (backend)
```
.
├── main.py                      # FastAPI app, CORS, router mount, static/admin mounts
├── start.sh                     # venv setup + uvicorn main:app --host 0.0.0.0 --port 8000
├── .env.example                 # env template (copy to .env, never commit .env)
├── requirements.txt             # python deps
├── README.md                    # project readme
├── admin/                       # admin panel (single HTML + inline JS/CSS)
│   └── index.html
├── static/uploads/              # local file storage (created at runtime)
│   ├── profiles/                # user profile pictures
│   └── hosts/
│       ├── pics/                # host gallery images + profile pic
│       └── videos/              # host preview/call/gallery videos
├── app/
│   ├── __init__.py
│   ├── core/
│   │   ├── config.py            # pydantic-settings, all env vars + AI settings
│   │   ├── database.py          # motor client, connect_db, indexes
│   │   └── security.py          # JWT, bcrypt, HTTPBearer deps
│   ├── routers/                 # one router per feature
│   │   ├── auth.py              # register/login/guest/me/profile/convert-guest
│   │   ├── hosts.py             # discover + admin host CRUD + media
│   │   ├── calls.py             # initiate/answer/billing-check/end/incoming/history
│   │   ├── wallet.py            # balance/packages/recharge/transactions/admin approve
│   │   ├── gifts.py             # gift list/send/admin CRUD/stats
│   │   ├── chat.py              # Priya bot + inbox + random match
│   │   ├── admin.py             # admin login/dashboard/users/analytics/notifications
│   │   ├── settings.py          # app settings (public + admin)
│   │   ├── upid_module.py       # single UPI ID config
│   │   └── levels.py            # XP levels + leaderboard
│   ├── services/
│   │   └── ai_bot.py            # LLM call + rule-based Hindi/Hinglish fallback
│   └── utils/
│       ├── helpers.py           # serialize_doc, validate_mobile, normalize_mobile, XP
│       └── media.py             # save_upload/save_many/delete_media_file (local disk)
└── venv/                        # virtualenv (gitignored)
```

### Run / Deploy
```bash
# 1. .env banayein (.env.example se copy, real values bharein)
cp .env.example .env
# SECRET_KEY (min 32 char) aur ADMIN_PASSWORD zaroor set karein

# 2. start.sh chalaayein (ye venv banata hai, deps install karta hai, directories create karta hai, fir uvicorn start karta hai)
bash start.sh
# ya seedha:
# uvicorn main:app --host 0.0.0.0 --port 8000 --reload --proxy-headers --forwarded-allow-ips="*"

# 3. URLs
# API:        http://localhost:8000
# Swagger:    http://localhost:8000/docs
# Admin:      http://localhost:8000/admin-panel   (login: admin / Admin@123)
```

### .env Variables (sirf naam, values nahi)
```text
MONGODB_URL
DATABASE_NAME
SECRET_KEY
ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES
ADMIN_USERNAME
ADMIN_PASSWORD
UPLOAD_DIR
MAX_FILE_SIZE
MAX_VIDEO_SIZE
MONGODB_TLS
AI_API_KEY
AI_BASE_URL
AI_MODEL
AI_TIMEOUT_SECONDS
AI_MAX_HISTORY
```
> `SECRET_KEY` aur `ADMIN_PASSWORD` bina set kiye app start nahi hogi (`config.py` me `RuntimeError` uthata hai).

---

## 2. Har API Endpoint (method, path, auth, body, response example)

Sabke peeche prefix `/api/v1` hai.

### Auth (`app/routers/auth.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 1 | POST | `/auth/register` | No | `Form`: name, mobile, password, gender, profile_picture(file) | `{success:true, message:"Registration successful", access_token, token_type:"bearer", user:{...}}` |
| 2 | POST | `/auth/login` | No | `Form`: mobile, password | `{success:true, message:"Login successful", access_token, token_type, user:{...}}` |
| 3 | POST | `/auth/guest-login` | No | — | `{success:true, message, access_token, user:{is_guest:true}, guest_limitations:[...]}` |
| 4 | GET | `/auth/me` | User | — | `{success:true, user:{...}}` |
| 5 | PUT | `/auth/profile` | User | `Form`: name?, gender?, interests?, profile_picture?(file) | `{success:true, message:"Profile updated", user:{...}}` |
| 6 | POST | `/auth/convert-guest` | User | `Form`: name, mobile, password | `{success:true, message:"Account converted successfully!..."}` |

### Hosts (`app/routers/hosts.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 7 | GET | `/hosts/discover` | Optional | Query: page, limit, interest?, gender?, level?, sort_by? | `{success:true, hosts:[{id,name,price_per_minute,images[],videos[],call_video,has_call_video,...}], total, page, ...}` |
| 8 | GET | `/hosts/featured` | No | — | `{success:true, hosts:[...]}` |
| 9 | GET | `/hosts/online` | No | — | `{success:true, hosts:[...], count}` |
| 10 | GET | `/hosts/{host_id}` | No | — | `{success:true, host:{...}}` |
| 11 | POST | `/hosts/admin/add` | Admin | `Form`: name, age, gender, level, price_per_minute, bio, description, city, interests, language, is_online, is_featured, bot_enabled, bot_greeting, call_message, bot_personality, bot_instructions + files profile_picture/preview_video/call_video/images[]/videos[] | `{success:true, message:"Host added successfully", host:{...}}` |
| 12 | PUT | `/hosts/admin/{host_id}` | Admin | `Form` (fields optional) + files + `clear_fields` | `{success:true, message:"Host updated", host:{...}}` |
| 13 | DELETE | `/hosts/admin/{host_id}/media` | Admin | Query: url, kind(image/video/call_video/preview_video/profile_picture) | `{success:true, message:"Media removed", host:{...}}` |
| 14 | DELETE | `/hosts/admin/{host_id}` | Admin | — | `{success:true, message:"Host deleted"}` |
| 15 | GET | `/hosts/admin/list/all` | Admin | Query: page, limit | `{success:true, hosts:[admin_host...], total}` |
| 16 | GET | `/hosts/admin/{host_id}` | Admin | — | `{success:true, host:{... (includes bot_personality/bot_instructions)}}` |

### Calls (`app/routers/calls.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 17 | POST | `/calls/initiate` | User | JSON: `{host_id, call_type:"outgoing\|incoming"}` | `{success:true, message:"Call initiated. Connecting...", host_message:{...}, call:{call_id,...}, call_id, call_type, your_balance, price_per_minute, estimated_max_minutes, estimated_max_seconds, call_video, connecting_seconds, billing_tick_seconds}` |
| 18 | POST | `/calls/answer/{call_id}` | User | — | `{success:true, message:"Call connected", start_time, balance, seconds_remaining}` |
| 19 | POST | `/calls/billing-check` | User | JSON: `{call_id}` | `{success:true, action:"continue", deducted, total_cost, new_balance, seconds_remaining, elapsed_seconds, warning?}`<br>or `{success:false, action:"end_call", reason:"insufficient_balance"\|"connection_lost", ...}` |
| 20 | POST | `/calls/end` | User | JSON: `{call_id, rating?, review?}` | `{success:true, message:"Call ended", status, duration_seconds, total_cost, new_balance, xp_gained, level_info?}` |
| 21 | GET | `/calls/random-host` | User | — | `{success:true, incoming_call:true, host:{...}, message:"X is calling you!", price_per_minute, ring_timeout_seconds}` |
| 22 | POST | `/calls/incoming/respond` | User | JSON: `{host_id, action:"rejected\|missed"}` | `{success:true, status:"rejected"}` |
| 23 | GET | `/calls/history` | User | Query: page, limit | `{success:true, calls:[{call_id,status,total_cost,duration_seconds,...}], total, page}` |
| 24 | GET | `/calls/admin/all` | Admin | Query: page, limit | `{success:true, calls:[...], total, stats:{total_completed_calls,total_revenue,avg_duration_seconds}}` |

### Wallet (`app/routers/wallet.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 25 | GET | `/wallet/balance` | User | — | `{success:true, balance, currency:"coins", user_id}` |
| 26 | GET | `/wallet/packages` | No | — | `{success:true, packages:[{id:"pack_100", coins:100, price:89, bonus:10, label:"Basic Pack"}, ...]}` |
| 27 | POST | `/wallet/recharge` | User | JSON: `{amount, payment_method:"upi", transaction_ref?}` | `{success:true, message:"...Coins will be credited after admin verifies...", request_id, amount_inr, coins_to_receive, bonus_coins, status:"pending", pay_to_upid}` |
| 28 | GET | `/wallet/my-recharges` | User | Query: page, limit | `{success:true, recharges:[{status:"pending/approved/rejected",...}], total, page}` |
| 29 | GET | `/wallet/transactions` | User | Query: page, limit, txn_type?(credit\|debit) | `{success:true, transactions:[{type,amount,description,balance_before,balance_after,created_at}], total, page}` |
| 30 | POST | `/wallet/admin/credit` | Admin | JSON: `{user_id, amount, reason:"Admin Credit"}` | `{success:true, message:"X coins credited", new_balance}` |
| 31 | GET | `/wallet/admin/all-transactions` | Admin | Query: page, limit | `{success:true, transactions:[...], total, stats:{credit:{total,count},debit:{total,count}}}` |
| 32 | GET | `/wallet/admin/recharges` | Admin | Query: status?(pending\|approved\|rejected), page, limit | `{success:true, recharges:[...], total, pending_count, page}` |
| 33 | POST | `/wallet/admin/recharges/{request_id}/approve` | Admin | — | `{success:true, message:"X coins credited to user", new_balance}` |
| 34 | POST | `/wallet/admin/recharges/{request_id}/reject` | Admin | JSON body?: `{reason?}` | `{success:true, message:"Recharge request rejected"}` |
| 35 | GET | `/wallet/qr-config` | No | — | `{success:true, upi_id, qr_image_url}` |
| 36 | POST | `/wallet/qr-config` | Admin | JSON: `{upi_id, qr_image_url}` | `{success:true, message:"QR config saved"}` |
| 37 | POST | `/wallet/deposit` | User | multipart: `{amount, transaction_ref, screenshot}` | `{success:true, deposit_id, status:"pending", message:"Deposit request submitted"}` |
| 38 | GET | `/wallet/my-deposits` | User | Query: page, limit | `{success:true, deposits:[{status,amount,transaction_ref,screenshot_url,admin_note,created_at}], total, page}` |
| 39 | GET | `/wallet/admin/deposits` | Admin | Query: status?, page, limit | `{success:true, deposits:[{user_id,user_name,amount,transaction_ref,status,created_at}], total, pending_count, page}` |
| 40 | POST | `/wallet/admin/deposits/{deposit_id}/approve` | Admin | JSON: `{amount}` | `{success:true, message:"₹X credited as coins", coins_credited, new_balance}` |
| 41 | POST | `/wallet/admin/deposits/{deposit_id}/reject` | Admin | JSON: `{reason?}` | `{success:true, message:"Deposit request rejected"}` |

### Gifts (`app/routers/gifts.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 42 | GET | `/gifts/list` | No | — | `{success:true, gifts:[{id,name,emoji,coins,category,animation,is_active,total_sent}]}` |
| 43 | GET | `/gifts/categories` | No | — | `{success:true, categories:[{category, gifts:[...]}]}` |
| 44 | POST | `/gifts/send` | User | JSON: `{gift_id, host_id, call_id?, message?}` | `{success:true, message:"🎁 Rose 🌹 sent to X!", gift:{...}, coins_spent, new_balance, animation, xp_gained}` |
| 45 | GET | `/gifts/my-history` | User | — | `{success:true, gifts:[{sender_name,host_name,gift_name,coins,created_at}], ...}` |
| 46 | POST | `/gifts/admin/add` | Admin | JSON: `{name, emoji, coins, category, is_active, animation?}` | `{success:true, message:"Gift added", gift:{...}}` |
| 47 | PUT | `/gifts/admin/{gift_id}` | Admin | JSON body?: `{name?, coins?, is_active?}` | `{success:true, message:"Gift updated"}` |
| 48 | GET | `/gifts/admin/stats` | Admin | — | `{success:true, top_gifts:[...], total_gifts_sent, total_coins_from_gifts}` |

### Chat / AI (`app/routers/chat.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 49 | GET | `/chat/bot/persona` | User | Query: host_id? | `{success:true, persona:{name,host_id,is_default,avatar,greeting,host:public_host?,ai_powered}}` |
| 50 | POST | `/chat/bot/message` | User | JSON: `{message, conversation_id?, host_id?}` | `{success:true, conversation_id, bot_reply, bot_name, host_id, your_message, language, ai_powered, xp_gained}` |
| 51 | GET | `/chat/bot/history/{conversation_id}` | User | — | `{success:true, conversation:{messages:[{sender,message,timestamp}],...}}` |
| 52 | GET | `/chat/bot/thread` | User | Query: host_id? | `{success:true, conversation_id, messages:[...], persona:{...}}` |
| 53 | GET | `/chat/inbox` | User | — | `{success:true, items:[{host_id,name,avatar,is_online,last_message,last_sender,last_time,unread}], total_unread}` |
| 54 | GET | `/chat/bot/my-conversations` | User | — | `{success:true, conversations:[{...}]}` |
| 55 | POST | `/chat/bot/new-session` | User | JSON body?: `{host_id?}` | `{success:true, conversation_id, greeting, bot_name, persona:{...}}` |
| 56 | POST | `/chat/admin/bot-test` | Admin | JSON: `{message, host_id?, history:[...]}` | `{success:true, reply, ai_powered, language, persona_name, system_prompt}` |
| 57 | POST | `/chat/random-match` | User | JSON: `{interest?}` | `{success:true, message:"Match mila! ...", matched_host:{...}, price_per_minute, action:"initiate_call"}` |
| 58 | GET | `/chat/random-match/interests` | No | — | `{success:true, interests:["music","movies",...]}` |

### Admin (`app/routers/admin.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 59 | POST | `/admin/login` | No | JSON: `{username, password}` | `{success:true, message:"Admin login successful", access_token, token_type:"bearer", admin:{username,role:"admin"}}` |
| 60 | GET | `/admin/dashboard` | Admin | — | `{success:true, dashboard:{users:{total,registered,guests,blocked,new_today,...}, hosts:{total,active,online}, calls:{total,completed,today,completion_rate}, revenue:{total_coins_recharged,today_inr,this_month_inr}, gifts:{total_sent,today}, top_users_by_balance:[...]}}` |
| 61 | GET | `/admin/users` | Admin | Query: page, limit, search?, is_blocked?, is_guest? | `{success:true, users:[{id,name,mobile,wallet_balance,...(password excluded)}], total, page, total_pages}` |
| 62 | GET | `/admin/users/{user_id}` | Admin | — | `{success:true, user:{...(password excluded)}, stats:{calls_made,total_gifts}, recent_transactions:[...]}` |
| 63 | POST | `/admin/users/block` | Admin | JSON: `{user_id, reason?}` | `{success:true, message:"User blocked. Reason: ..."}` |
| 64 | POST | `/admin/users/unblock/{user_id}` | Admin | — | `{success:true, message:"User unblocked successfully"}` |
| 65 | DELETE | `/admin/users/{user_id}` | Admin | — | `{success:true, message:"User deleted"}` |
| 66 | GET | `/admin/analytics` | Admin | Query: days?(30) | `{success:true, period_days, analytics:{daily_registrations:[{_id:date,count}], daily_calls:[{_id,count,revenue}], daily_recharges:[{_id,count,amount}]}}` |
| 67 | POST | `/admin/notifications/send` | Admin | JSON: `{title, message, target:"all"\|"specific_user", user_id?}` | `{success:true, message:"Notification sent successfully"}` |
| 68 | GET | `/admin/notifications` | Admin | — | `{success:true, notifications:[{title,message,target,user_id,sent_at}]}` |

### Settings (`app/routers/settings.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 69 | GET | `/settings/app` | No (public) | — | `{success:true, settings:{connecting_seconds,billing_tick_seconds,...,priya_name}}` |
| 70 | GET | `/settings/admin` | Admin | — | `{success:true, settings:{...all defaults+overrides}, ai:{configured,model,base_url}}` |
| 71 | PUT | `/settings/admin` | Admin | JSON: `{connecting_seconds?,billing_tick_seconds?,...,priya_bot?:{name,greeting,personality,instructions}}` | `{success:true, message:"Settings saved", settings:{...}}` |

### UPID (`app/routers/upid_module.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 72 | POST | `/upid/add` | Admin | JSON body (upid string) | `{success:true, message:"UPID created", upid:"9876543210@upi"}` |
| 73 | GET | `/upid/get` | Any authenticated | — | `{success:true, upid:"..."}` |
| 74 | PUT | `/upid/update` | Admin | JSON body (upid string) | `{success:true, message:"UPID updated", upid:"..."}` |

### Levels (`app/routers/levels.py`)
| # | Method | Path | Auth | Request Body | Response Example |
|---|--------|------|------|--------------|------------------|
| 75 | GET | `/levels/my-level` | User | — | `{success:true, level:{level,title,xp,next_level_xp,progress_percent}, badge, perks, xp_actions:[...]}` |
| 76 | GET | `/levels/leaderboard` | No | — | `{success:true, leaderboard:[{rank,name,level,level_title,xp,profile_picture,id}]}` |
| 77 | GET | `/levels/all-levels` | No | — | `{success:true, levels:[{level,title,min_xp,max_xp,badge,perks}], xp_actions:[...]}` |

---

## 3. Database Models / Collections (MongoDB, schemaless — fields ki list)

### `users`
`name, mobile, username, password(bcrypt), gender, profile_picture, wallet_balance, xp, level, level_title, is_blocked, is_guest, interests[], call_count, total_call_minutes, gifts_sent, gifts_received, created_at, last_login, daily_login_date`
*(extra admin fields: `block_reason`, `blocked_at`)*

### `host_users`
`name, age, gender, level, level_title, price_per_minute, bio, description, city, interests[], language, profile_picture, preview_video, call_video, images[], videos[], bot_enabled, bot_greeting, call_message, bot_personality, bot_instructions, is_active, is_online, is_featured, total_calls, total_minutes, total_earnings, rating, review_count, created_at, updated_at`

### `call_logs`
`call_id, call_type("outgoing"\|"incoming"), caller_id, caller_name, host_id, host_name, price_per_minute, status("initiated"\|"ringing"\|"active"\|"completed"\|"ended_insufficient_balance"\|"timed_out"\|"cancelled"\|"rejected"\|"missed"), start_time, end_time, duration_seconds, billed_seconds, total_cost, balance_at_start, last_billing_check, rating?, review?, created_at`

### `transactions`
`user_id, type("credit"\|"debit"), amount, description, status("success"), balance_before, balance_after, created_at, base_amount?, bonus_coins?, payment_method?, transaction_ref?, recharge_request_id?`

### `recharge_requests`
`user_id, user_name, user_mobile, amount_inr, coins_to_credit, bonus_coins, package_id?, payment_method, transaction_ref, status("pending"\|"approved"\|"rejected"), created_at, approved_at?, rejected_at?, reject_reason?`

### `gifts`
`name, emoji, coins, category, animation, is_active, total_sent, created_at`

### `gift_logs`
`sender_id, sender_name, host_id, host_name, gift_id, gift_name, gift_emoji, coins, call_id?, message?, animation, created_at`

### `conversations`
`user_id, type("bot"), host_id?(null=Priya default), bot_name, messages[][{sender,message,timestamp,ai_powered?,language?}], unread, created_at, updated_at`

### `notifications`
`title, message, target, user_id?, sent_at, sent_by`

### `upid_config`
`upid, created_at, updated_at` (single document)

### `app_settings`
`_id="global"`, `connecting_seconds`, `billing_tick_seconds`, `heartbeat_grace_seconds`, `incoming_call_enabled`, `incoming_call_interval_seconds`, `incoming_ring_timeout_seconds`, `call_message_enabled`, `call_message`, `call_message_low_balance`, `priya_host_id`, `priya_bot{name,greeting,personality,instructions}`, `updated_at`

Indexes: `users.mobile` (unique partial), `users.username` (unique), `host_users.name`, `call_logs.call_id` (unique), `call_logs(caller_id, created_at)`, `call_logs(caller_id, status)`, `conversations(user_id, type, host_id, created_at)`, `transactions(user_id)`, `gifts(category)`, `recharge_requests(status, created_at)`.

---

## 4. Auth Kaise Kaam Karta Hai

- **Token type:** JWT (HS256), `Bearer` scheme, header `Authorization: Bearer <token>`.
- **Expiry:** `ACCESS_TOKEN_EXPIRE_MINUTES` (default `10080` = 7 dın).
- **Password:** bcrypt (12 rounds, 72-byte truncate).
- **Token payload:** `{"sub": "<user ObjectId>", "role": <null or "admin">, "exp": ...}`.
- **Register:** mobile normalize (`+91 98765-43210` → `9876543210`), validate `^[6-9]\d{9}$`, unique mobile check, password min 4 chars, hash + insert, issue token, return user.
- **Login:** normalize mobile, find user, `verify_password`, block check → 403, daily-login XP bonus (+5, level recalc), issue fresh token, return user.
- **Guest:** `mobile: null`, `is_guest: true`, cannot call/recharge/send gifts, token issued same way.
- **Convert guest:** sets name/mobile/password, `is_guest=false`.
- **Dependencies:** `get_current_user` (401 if no token/invalid/blocked), `get_current_admin` (role=="admin"), `get_any_authenticated` (user OR admin). `HTTPBearer(auto_error=False)` → missing header gives **401** (not FastAPI default 403).

---

## 5. Admin Panel (`admin/index.html`) Mein Kya-Kya Manage Hota Hai

Ek single-file HTML admin panel (`/admin-panel`), FastAPI static mount se serve hota hai.

Manage karne cheezein:
- **Dashboard:** users (total/registered/guests/blocked/new), hosts (total/active/online), calls (total/completed/today/rate), revenue (coins/INR today & month), gifts, top users by balance.
- **Users:** list with search/filters (blocked/guest), user detail, block/unblock, delete user, recent transactions.
- **Hosts:** add host (name, age, gender, level, price/min, bio, description, city, interests, language, online/featured, bot on/off, greeting, call_message, bot_personality, bot_instructions, media uploads), update, delete, delete single media, list all (incl. inactive).
- **Settings:** app settings (call timings, incoming interval, priya persona), AI configured/model/base_url view.
- **Wallet:** all transactions, recharge requests list (pending/approved/rejected), approve/reject recharge, admin credit user.
- **Gifts:** add/update gift, stats.
- **Calls:** all calls list + stats.
- **Notifications:** send notification (title/message/target/user_id), view sent list.
- **UPID:** create/get/update single UPI ID (admin only for create/update; any authenticated can read).
- **Analytics:** 30-day daily registrations/calls/recharges charts.

> Admin login: `POST /api/v1/admin/login` with `ADMIN_USERNAME` / `ADMIN_PASSWORD` from `.env`.

---

## 6. Call Flow: Outgoing / Incoming, Wallet Deduction Per Second, Auto-End

### Outgoing call
1. `POST /calls/initiate` `{host_id, call_type:"outgoing"}` — guest → 403; host inactive → 404; offline → 400; balance < price_per_minute → **402** (insufficient balance, pushes low-balance host message to inbox).
2. Close any stale in-progress calls for this user (`_close_stale_calls`).
3. Create `call_logs` doc: `status="initiated"`, `start_time=null`, `total_cost=0`.
4. Push host message to user's inbox (`push_host_message`, kind="call") — host ka message turant Inbox mein aata hai.
5. App dikhati hai **"Calling… / Connecting…"** screen for `connecting_seconds` (default 10s). **Ye billed nahi hota.**
6. User taps accept → `POST /calls/answer/{call_id}` → `status="active"`, `start_time=now`, billing clock start. App play karti hai host ka `call_video` (fallback: `preview_video` → first gallery video).
7. App har `billing_tick_seconds` (default 5s) par `POST /calls/billing-check` `{call_id}` bhejti hai. Server pro-rata charge karta hai (`price_per_minute/60` per second), atomic conditional debit. Agar balance khatam → `action:"end_call"`, `reason:"insufficient_balance"`, call `ended_insufficient_balance`.
8. Warning: `seconds_remaining <= 60` → "Low balance! ..." snackbar.
9. User cuts → `POST /calls/end` → final settlement, rating, XP (+10 `call_made`), host earnings update. Agar connecting screen pe cancel hua (no `start_time`) → **free**, `status="cancelled"`.
10. Agar app disconnect ho jaaye (no heartbeat) → `heartbeat_grace_seconds` (default 45s) baad `timed_out`, billed sirf elapsed tak.

### Incoming call
1. `GET /calls/random-host` — random online host (prefers hosts with `call_video`), `ring_timeout_seconds` (default 30s).
2. App dikhati hai incoming call screen (Accept/Reject).
3. Accept → `POST /calls/initiate` `{call_type:"incoming"}` (same flow as outgoing).
4. Reject/Missed → `POST /calls/incoming/respond` `{host_id, action:"rejected"\|"missed"}` → logged in `call_logs`, no charge.
5. Auto-incoming: app-side `IncomingCallService` har `incoming_call_interval_seconds` (default **300s = 5 min**) par random-host fetch karke incoming screen dikhati hai (sirf jab app open & in use ho).

### Wallet deduction logic (server-side, race-safe)
- `_debit()`: `find_one_and_update({_id, wallet_balance: {$gte: amount}}, {$inc: -amount})` — atomic.
- Agar full amount nahi milta → `_drain()`: jo bacha hai wo le, balance 0, call end.
- Ek call ke liye **ek transaction record** accumulate hota hai (`call_id` + type=debit, upsert), nahi ki har tick pe naya row.
- `₹1 = 1 coin`. Custom recharge: 1 INR = 1 coin, no bonus.

---

## 7. AI Chat (Priya): LLM, Prompt, Admin Persona Fields

### LLM
- Koi bhi **OpenAI-compatible Chat Completions API** (OpenAI, Groq, OpenRouter, Gemini-OpenAI, Ollama).
- Env: `AI_API_KEY`, `AI_BASE_URL` (default `https://api.openai.com/v1`), `AI_MODEL` (default `gpt-4o-mini`), `AI_TIMEOUT_SECONDS` (25), `AI_MAX_HISTORY` (16).
- Agar `AI_API_KEY` khali hai ya provider fail ho jaye → **built-in rule-based fallback bot** Hindi (Devanagari) / English / Hinglish mein jawab deta hai.
- Call: `httpx.AsyncClient` POST `{base_url}/chat/completions`, `Bearer {AI_API_KEY}`.

### Prompt kahan banta hai
`app/services/ai_bot.py` → `build_system_prompt(persona)`. System prompt mein persona details (age, gender, city, language, interests, bio, description, personality, instructions, price/min), language rules (user ki bhasha mein jawab), conversation rules (short 1-3 sentences, emoji sparingly, no explicit/romantic content, no financial details, honest if asked "are you AI").

### Admin persona fields (konse fields admin set kar sakta hai)
- **Per-host** (`host_users`): `bot_enabled`, `bot_greeting`, `bot_personality`, `bot_instructions` — admin panel ke "Bot / Chat context" section se.
- **Global/default** (`app_settings` → `priya_bot`): `name` (default "Priya"), `greeting`, `personality`, `instructions`. Plus optional `priya_host_id` — jin host ki profile Priya page ko power karegi.
- `resolve_persona()`: agar `host_id` diya → us host ka context; agar nahi → `priya_host_id` linked host; warna default `priya_bot`.
- `private fields` (`bot_personality`, `bot_instructions`) **public API mein nahi jate** (`PRIVATE_FIELDS` in hosts.py).

### Chat endpoints
`GET /chat/bot/persona`, `POST /chat/bot/message`, `GET /chat/bot/history/{id}`, `GET /chat/bot/thread`, `GET /chat/inbox`, `POST /chat/bot/new-session`, `POST /chat/admin/bot-test` (admin preview, system_prompt wapas karta hai).

---

## 8. Wallet / Recharge: Packs Kahan Se Aate Hain, Payment Gateway?

### Coin Packages
Hardcoded list `COIN_PACKAGES` in `app/routers/wallet.py` (7 packs):
`pack_50` (50 coins ₹49), `pack_100` (100+10 bonus ₹89), `pack_250` (250+30 ₹199), `pack_500` (500+75 ₹379), `pack_1000` (1000+200 ₹699), `pack_2000` (2000+500 ₹1299).
`GET /wallet/packages` inka list deta hai. Custom amount → 1 INR = 1 coin, no bonus.

### Payment Gateway
**Koi real payment gateway integrate nahi hai.** Flow:
1. User `POST /wallet/recharge` `{amount, payment_method:"upi", transaction_ref?}` → `recharge_requests` mein `status="pending"` row banti hai. Response mein `pay_to_upid` (admin-set single UPI ID) milta hai.
2. User UPI se payment kare, ref/UTR bhej sake.
3. Admin `GET /wallet/admin/recharges` se pending list dekhta hai, payment verify karke `POST /.../approve` → `wallet_balance` atomic credit + `transactions` credit row. `POST /.../reject` → status rejected.
4. Coins sirf admin approval ke baad credit hote hain (instant credit ka purana bug fix ho chuka hai).

### UPID
Single UPI ID config in `upid_config` collection. `POST /upid/add` (admin), `GET /upid/get` (any authenticated), `PUT /upid/update` (admin). Regex: `something@bank` (e.g. `9876543210@upi`).

---

## 9. File Upload / Storage (Images, Videos)

- **Storage:** Local disk only (`static/uploads/`), served via FastAPI `/static` static mount.
  - `static/uploads/profiles/` — user profile pictures.
  - `static/uploads/hosts/pics/` — host gallery images + profile pic.
  - `static/uploads/hosts/videos/` — host preview/call/gallery videos.
- **Validation:** `app/utils/media.py`.
  - Images: `jpg, jpeg, png, webp, gif`, max **10 MB** (`MAX_FILE_SIZE`).
  - Videos: `mp4, webm, mov, m4v`, max **100 MB** (`MAX_VIDEO_SIZE`).
- **Upload:** streamed in 1 MB chunks via `aiofiles` (bada video memory mein nahi uthta). Size check likhte waqt (413 if too large). Filename = `uuid.ext`.
- **URL:** `/static/uploads/hosts/pics/<uuid>.jpg` jaisa public URL.
- **Delete:** `delete_media_file(url)` — best-effort, sirf jab host mein kahin bhi reference na ho (profile_picture/preview_video/call_video/images/videos mein check).
- Profile update / host update mein nayi images/videos gallery mein append hoti hain (`$push`), purane remove hote hain (`$pull`) media-delete endpoint se.

---

## 10. Flutter App Structure (Client Side)

### State management
`provider` package. `main.dart` mein `MultiProvider` — sab providers ek hi `ApiService` instance share karte hain.

### Providers (`flutter_app/lib/providers/`)
| Provider | Kaam |
|----------|------|
| `AuthProvider` | login/register/guest/me/profile/convert, token save/load (`shared_preferences`), `init()` session restore |
| `HostProvider` | discover/featured/online/host-detail + admin host CRUD |
| `WalletProvider` | balance, packages, recharge, transactions |
| `CallProvider` | initiate/answer/billing-check/end/history, `onHostMessage` callback → inbox reload |
| `IncomingCallService` | har 5 min random-host fetch, incoming screen show (navigatorKey), call accept/reject |
| `ChatProvider` | bot persona/message/history/thread/inbox/new-session |
| `InboxProvider` | chat inbox load, unread count |
| `GiftProvider` | gift list/send/history |
| `LevelProvider` | my-level, leaderboard, all-levels |
| `AppSettingsProvider` | public + admin app settings |

### API Service (`flutter_app/lib/services/api_service.dart`)
- `http.Client` shared, `followRedirects=false`, manual redirect follow (301/302/303/307/308, max 4 hops) — method, body, token retain hota hai; origin change pe `AppConfig.runtimeOrigin` update.
- Timeout 30s, uploads 120s.
- `ApiFile(field, bytes, filename)` class; `multipart(method, path, {fields, files})`.
- Network/timeout → `ApiException(0, ...)` clear Hinglish message; non-JSON / 3xx → clear `ApiException`.
- `baseUrl` → `AppConfig.origin` (from `--dart-define=API_BASE_URL` or default `http://10.0.2.2:8000`).
- `onUnauthorized` callback → login screen (401 sirf jab token bheja ho, galat password pe "session expired" nahi).

### Screens (`flutter_app/lib/screens/`)
| Screen | APIs it calls |
|--------|---------------|
| `auth/LoginScreen` | `POST /auth/login`, `POST /auth/guest-login` |
| `auth/RegisterScreen` | `POST /auth/register` |
| `auth/ConvertGuestScreen` | `POST /auth/convert-guest` |
| `home/DiscoverScreen` | `GET /hosts/discover`, `GET /hosts/featured`, `GET /hosts/online` |
| `home/HostDetailScreen` | `GET /hosts/{id}` |
| `call/CallScreen` | `POST /calls/initiate`, `POST /calls/billing-check`, `POST /calls/end`, `GET /wallet/balance` |
| `call/IncomingCallScreen` | `GET /calls/random-host`, `POST /calls/incoming/respond`, `POST /calls/initiate` |
| `call/RandomMatchScreen` | `POST /chat/random-match` |
| `chat/ChatScreen` | `POST /chat/bot/message`, `GET /chat/bot/history/{id}` |
| `chat/InboxScreen` | `GET /chat/inbox`, `GET /chat/bot/thread` |
| `wallet/WalletScreen` | `GET /wallet/balance`, `GET /wallet/packages`, `POST /wallet/recharge`, `GET /wallet/transactions` |
| `profile/ProfileScreen` | `GET /auth/me`, `GET /wallet/balance` |
| `profile/EditProfileScreen` | `PUT /auth/profile` |
| `profile/CallHistoryScreen` | `GET /calls/history` |
| `levels/LeaderboardScreen` | `GET /levels/my-level`, `GET /levels/leaderboard`, `GET /levels/all-levels` |
| `gifts/GiftSheet` | `GET /gifts/list`, `POST /gifts/send` |
| `splash/SplashScreen` | auth init / auto-login |

### Widgets / Services
`widgets/widgets.dart`, `widgets/recharge_prompt.dart`, `services/incoming_call_service.dart`, `theme/app_theme.dart`, `config/app_config.dart`, `models/models.dart`.

---

## 11. Jo Cheezein Abhi Nahi Hain (Missing Features)

Ye features point 11 ki list se hain; backend support status:

| Feature | Backend Status |
|---------|----------------|
| OTP login | ✅ Present — `/auth/otp/send`, `/auth/otp/verify` (dev mode prints OTP) |
| Google login | ✅ Present — `/auth/google` |
| Follow / Block / Report | ✅ Present — follow, blocked-hosts, reports (+admin reports list) |
| Levels | ✅ Present — XP/level system + leaderboard (`/levels/*`) |
| DND (Do Not Disturb) | ✅ Present — `/users/me/settings` {dnd, languages} |
| Languages (user language setting) | ✅ Present — saved per user, used in for-you + bot persona |
| Live streaming | ❌ Absent — recorded `call_video` plays in call |
| Notifications (push/FCM) | ⚠️ Partial — DB save + FCM push if `FCM_SERVER_KEY` set; device registration `/users/me/device` |
| Delete account (self) | ✅ Present — `DELETE /auth/me` (soft delete + PII anonymise) |
| Host tabs (For You / All / New / Follow) | ✅ Present — `/hosts/discover?tab=` |

---

## 12. OnlineDost — Naye Backend Endpoint (Additive)

Sab `/api/v1` prefix ke saath; purane endpoint apne jaane waise hi chal rahe hain.

### Auth (OTP / Google)
| Method | Path | Auth | Body | Response |
|--------|------|------|------|----------|
| POST | `/auth/otp/send` | No | `mobile` | `{success, mobile, expires_in_seconds}` |
| POST | `/auth/otp/verify` | No | `mobile, otp` | `{success, access_token, user, is_new_user}` |
| POST | `/auth/google` | No | `id_token` | `{success, access_token, user, is_new_user}` |
| DELETE | `/auth/me` | User | — | `{success, message:"Account deleted"}` |

Rate limits: OTP send 5/mobile-hr + 10/IP-hr; verify 3/mobile-hr; Google 10/IP-hr.

### Users (settings, blocked/hide, reports, device)
| Method | Path | Auth | Body | Response |
|--------|------|------|------|----------|
| GET | `/users/me/settings` | User | — | `{settings:{dnd,languages}}` |
| PUT | `/users/me/settings` | User | `{dnd?,languages?}` | `{settings:{...}}` |
| GET | `/users/me/blocked-hosts` | User | — | `{blocked:[{host_id,type}]}` |
| POST | `/users/me/blocked-hosts` | User | `{host_id}` | `{success, host_id}` |
| DELETE | `/users/me/blocked-hosts/{id}` | User | — | `{success}` |
| POST | `/reports` | User | `{host_id,reason,details?}` | `{success}` |
| GET | `/users/admin/reports` | Admin | Query status | `{reports:[...], total}` |
| POST | `/users/me/device` | User | `{fcm_token}` | `{success}` |

### Hosts (tabs, follow, new fields)
| Method | Path | Auth | Body | Response |
|--------|------|------|------|----------|
| GET | `/hosts/discover` | Optional | Query `tab=for_you\|all\|new\|follow` | `{hosts:[...], tab, total}` |
| POST | `/hosts/{id}/follow` | User | — | `{success}` |
| DELETE | `/hosts/{id}/follow` | User | — | `{success}` |
| GET | `/hosts/following` | User | — | `{following:[...]}` |

Host model gained: `languages[]`, `country`, `host_type`, `email`, `google_sub`.

### Wallet (packs, Razorpay, transactions)
| Method | Path | Auth | Body | Response |
|--------|------|------|------|----------|
| GET | `/wallet/packages` | No | — | `{packages:[{id,pay_amount,get_amount,bonus,is_best}]}` |
| POST | `/wallet/pay/create-order` | User | `{pack_id\|amount}` | `{order_id,amount,key_id,pay_amount,get_amount}` |
| POST | `/wallet/pay/verify` | User | `{razorpay_order_id,razorpay_payment_id,razorpay_signature}` | `{success,credited,get_amount}` |
| POST | `/wallet/pay/webhook` | No (sig) | Razorpay webhook | `{success}` |
| GET | `/wallet/pay/upi-qr` | User | Query amount | `{upi_url,amount}` |
| GET | `/wallet/transactions` | User | `last_days?(90)` | `{transactions:[...]}` |
| POST | `/wallet/admin/packs` | Admin | Pack fields | `{pack}` |
| PUT/DELETE | `/wallet/admin/packs/{id}` | Admin | Pack fields | `{success}` |

Packs collection `talktime_packs`: `{pay_amount,get_amount,bonus,is_best,sort,is_active}`.

### Static pages
| Method | Path | Auth | Body | Response |
|--------|------|------|------|----------|
| GET | `/pages/{slug}` | No | — | `{page:{slug,title,content}}` |
| PUT | `/pages/admin/{slug}` | Admin | `{title?,content}` | `{page}` |

Slugs: `privacy-policy`, `terms`, `community-guidelines`, `content-moderation`, `compliance`, `subscription-privacy`, `refund-cancellation`.

### Calls (rate limit)
| Method | Path | Auth | Note |
|--------|------|------|------|
| POST | `/calls/billing-check` | User | Rate limited 60/min/user |

### New collections
`otps`, `follows`, `blocked_hosts`, `reports`, `devices`, `talktime_packs`, `pages`, `payments`.

---

## 🔴 Remaining Gaps (still not in backend)

1. **Real-time / WebSockets** — no call signaling, incoming-call push, or live chat push.
2. **Live streaming** — not implemented (item n is Flutter "Coming soon" only).
3. **Email field** — user model has no email.
4. File storage still local disk only.

Yeh audit sirf samajh aur documentation ke liye hai; isse koi code nahi badla gaya.

