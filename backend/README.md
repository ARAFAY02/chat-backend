# Chat Demo Backend (FastAPI + WebSocket)

A minimal, in-memory WebSocket relay for the Flutter 1-to-1 chat demo.
No database, no Redis — just enough to prove real-time messaging works
between two Flutter clients. See comments in `main.py` for where a DB
or Redis would plug in later.

## 1. Install dependencies

```bash
cd backend
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## 2. Run the server

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` is required (not `127.0.0.1`) so that other devices on
your Wi-Fi network (or an emulator's virtual network) can reach it.

You should see:

```
INFO:     Uvicorn running on http://0.0.0.0:8000
```

Health check: open `http://localhost:8000/` in a browser — it returns
a JSON blob with currently online users.

## 3. Find your Mac's local IP address

```bash
ipconfig getifaddr en0
```

(`en0` is usually Wi-Fi on a Mac; use `en1` if you're on a different
adapter, or check `ifconfig` for the interface with your LAN IP,
something like `192.168.x.x`.)

You'll plug this IP into the Flutter app's `AppConstants.serverHost`.

## 4. Configuring the Flutter app to find this server

Open `flutter_app/lib/utils/app_constants.dart` and set:

```dart
static const String serverHost = '192.168.1.23'; // <- your Mac's IP
```

### Emulator vs physical device — this is the part people get wrong

**Android Emulator**
The emulator does NOT share your Mac's `localhost`. It has its own
virtual network.
- If your server runs on your Mac and you're testing from the Android
  emulator, use your Mac's real LAN IP (`192.168.x.x`), same as a
  physical device — the emulator is bridged onto your Wi-Fi network by
  default in modern Android Studio setups.
- Special case: `10.0.2.2` is a magic alias the Android emulator maps
  to your host machine's `localhost`. So if you're running the backend
  locally and only testing on ONE Android emulator, `10.0.2.2` also
  works. But if you're running TWO emulators/devices talking to each
  other, use the real Mac LAN IP for both so they resolve to the same
  server.

**iOS Simulator**
The iOS Simulator shares your Mac's network stack directly, so
`localhost` or `127.0.0.1` works fine — but for consistency (and so
the same build works on a physical iPhone too), still use your Mac's
LAN IP.

**Physical devices (Android phone / iPhone)**
The phone must be on the **same Wi-Fi network** as your Mac. Use the
Mac's LAN IP from step 3. `localhost` will NOT work — that would point
the phone at itself.

**Firewall**
On first run, macOS may prompt to allow incoming connections for
Python — click Allow, or the server won't be reachable from other
devices.

## 5. Running two clients at once

You need two separate instances of the Flutter app, each logged in as
a different demo user (`user_1` / Abdul Rafay and `user_2` / Khizar
Hussain — see the dev login screen in the app). Options:

- One Android emulator + one iOS Simulator, running side by side.
- Two Android emulators (`flutter emulators --launch <id>` twice with
  different AVDs).
- One emulator + one physical device.
- Two physical devices.

Run the app on each target from a separate terminal tab:

```bash
cd flutter_app
flutter run -d <device_id_1>
flutter run -d <device_id_2>
```

(`flutter devices` lists available device IDs.)

On each app instance, pick a different demo user at the login screen,
then open a chat with the other user and send messages back and
forth. Messages, typing indicators, and online/offline status should
update instantly on both ends.

## How the message flow works

```
Flutter Client A                 FastAPI Server                Flutter Client B
      |                                |                              |
      | ws connect /ws/user_1         |                              |
      |------------------------------>|                              |
      |                                |  ws connect /ws/user_2      |
      |                                |<-----------------------------|
      |                                |                              |
      | {"type":"message", ...}       |                              |
      |------------------------------>|                              |
      |                                | look up user_2's socket     |
      |                                |----------------------------->|
      |                                |                              |
      |   {"type":"sent/delivered"}   |                              |
      |<-------------------------------|                              |
```

Each client holds one persistent WebSocket connection, identified by
`user_id` in the URL path (`/ws/{user_id}`). The server keeps an
in-memory map of `user_id -> WebSocket` (`ConnectionManager` in
`main.py`). When a message arrives, the server looks up the
receiver's socket and forwards the JSON payload directly — no
polling, no REST calls, no delay beyond the network hop itself.
