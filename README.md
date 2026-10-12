# Real-Time 1-to-1 Chat Demo

Flutter (client) + Python FastAPI WebSocket (server). Two Flutter app
instances connect to one local backend and exchange messages, typing
indicators, and online/offline status instantly — no Firebase, no
polling, no third-party chat SDK.

```
chat_demo/
├── flutter_app/     # Flutter mobile app (see below)
└── backend/         # FastAPI WebSocket server (see backend/README.md)
```

## Quick start

1. **Start the backend** — full instructions in `backend/README.md`:
   ```bash
   cd backend
   python3 -m venv venv && source venv/bin/activate
   pip install -r requirements.txt
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```

2. **Point the Flutter app at your machine's IP** — edit
   `flutter_app/lib/utils/app_constants.dart`:
   ```dart
   static const String serverHost = '192.168.1.23'; // your LAN IP
   ```

3. **Install Flutter deps and run two clients**:
   ```bash
   cd flutter_app
   flutter pub get
   flutter devices                  # list available targets
   flutter run -d <device_id_1>     # terminal tab 1
   flutter run -d <device_id_2>     # terminal tab 2
   ```

4. On each running app, pick a different demo user (Abdul Rafay /
   Khizar Hussain) at the login screen, open the chat, and start
   messaging. Everything updates live: message delivery, ticks
   (sent/delivered/seen), typing indicator, and the online dot.

## How it works, end to end

- Each Flutter client opens one persistent WebSocket to
  `ws://<server>:8000/ws/{user_id}` using `dart:io`'s built-in
  `WebSocket` (`lib/services/websocket_service.dart`) — no extra
  WebSocket package.
- The FastAPI backend (`backend/main.py`) keeps an in-memory
  `user_id -> WebSocket` map. When it receives a `message` frame from
  one user, it looks up the receiver's socket and forwards the JSON
  payload directly to them.
- `ChatProvider` (`flutter_app/lib/providers/chat_provider.dart`) is
  the single `ChangeNotifier` that owns all chat state (messages,
  typing, online status, connection status). Screens/widgets only
  read from and call methods on the provider — never on the raw
  socket.
- If the connection drops, `WebSocketService` reconnects automatically
  with exponential backoff (2s → 4s → 8s ... capped at 30s), and the
  chat list app bar shows live connection status.

See `backend/README.md` for detailed emulator vs. physical-device
networking instructions — that's the part most people get stuck on.
