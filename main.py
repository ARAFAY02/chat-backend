"""
Lightweight FastAPI WebSocket backend for the 1-to-1 chat demo.

Design notes (for future extension):
- All LIVE connection state (who's online right now) lives in
  ConnectionManager, in memory, keyed by user_id. This part is NOT
  persisted, and shouldn't be - it's only true while the process runs.
- Message HISTORY is persisted to a local SQLite database (chat_history.db,
  created automatically next to this file). Every message is saved as
  soon as it's sent, and its status (sent/delivered/seen) is updated in
  place as receipts come in. A REST endpoint (GET /messages/{a}/{b})
  lets a client fetch the full history for a conversation - used when a
  chat screen is opened, so old messages survive app restarts and
  backend restarts.
- To add Redis pub/sub for multi-instance scaling, ConnectionManager.send_to_user
  is the single choke point where a "local send" would become a
  "publish to Redis channel, and every instance forwards to its own
  local sockets" call. The rest of the app doesn't need to know about it.
"""

import json
import logging
from datetime import datetime, timezone
from typing import Optional

import aiosqlite
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chat-backend")

app = FastAPI(title="Realtime Chat Demo Backend")

# CORS is irrelevant for raw WebSocket connections from mobile clients,
# but harmless to leave open for local development tooling (e.g. a
# future web client or debug dashboard).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = "chat_history.db"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + \
        f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"


def chat_id_for(user_a: str, user_b: str) -> str:
    """Same deterministic chat-id scheme the Flutter client uses, so
    history saved here lines up with chat_id values the app sends."""
    ids = sorted([user_a, user_b])
    return f"chat_{ids[0]}_{ids[1]}"


# --------------------------------------------------------------------
# Persistence layer (SQLite)
# --------------------------------------------------------------------

async def init_db() -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                receiver_id TEXT NOT NULL,
                message TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                status TEXT NOT NULL
            )
            """
        )
        await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)"
        )
        await db.commit()
    logger.info("Database ready at %s", DB_PATH)


async def save_message(
    message_id: str,
    chat_id: str,
    sender_id: str,
    receiver_id: str,
    message: str,
    timestamp: str,
    status: str,
) -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            INSERT OR REPLACE INTO messages
                (id, chat_id, sender_id, receiver_id, message, timestamp, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (message_id, chat_id, sender_id, receiver_id, message, timestamp, status),
        )
        await db.commit()


async def update_message_status(message_id: str, status: str) -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "UPDATE messages SET status = ? WHERE id = ?",
            (status, message_id),
        )
        await db.commit()


async def fetch_history(chat_id: str, limit: int = 200) -> list[dict]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            """
            SELECT id, chat_id, sender_id, receiver_id, message, timestamp, status
            FROM messages
            WHERE chat_id = ?
            ORDER BY timestamp ASC
            LIMIT ?
            """,
            (chat_id, limit),
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]


@app.on_event("startup")
async def on_startup() -> None:
    await init_db()


# --------------------------------------------------------------------
# Live connection management (in-memory, unchanged)
# --------------------------------------------------------------------

class ConnectionManager:
    """Keeps track of connected users and routes messages between them.

    In-memory only, by design. One process, one dict. Fine for a local
    dev proof-of-concept with two demo users.
    """

    def __init__(self) -> None:
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, user_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections[user_id] = websocket
        logger.info("User connected: %s (total online: %d)", user_id, len(self.active_connections))

    def disconnect(self, user_id: str) -> None:
        self.active_connections.pop(user_id, None)
        logger.info("User disconnected: %s (total online: %d)", user_id, len(self.active_connections))

    def is_online(self, user_id: str) -> bool:
        return user_id in self.active_connections

    async def send_to_user(self, user_id: str, payload: dict) -> bool:
        """Send a JSON payload to a single user if they're connected.

        Returns True if delivered, False if the user isn't connected
        (the caller can decide what "not delivered" means, e.g. keep
        status as "sent" instead of "delivered").
        """
        websocket = self.active_connections.get(user_id)
        if websocket is None:
            return False
        try:
            await websocket.send_text(json.dumps(payload))
            return True
        except Exception:
            logger.exception("Failed to send to %s, dropping connection", user_id)
            self.disconnect(user_id)
            return False

    async def broadcast_presence(self, user_id: str, status: str) -> None:
        """Tell everyone else this user's online/offline status changed."""
        payload = {
            "type": status,  # "online" | "offline"
            "sender_id": user_id,
            "timestamp": now_iso(),
        }
        for other_id, ws in list(self.active_connections.items()):
            if other_id == user_id:
                continue
            try:
                await ws.send_text(json.dumps(payload))
            except Exception:
                logger.exception("Failed broadcasting presence to %s", other_id)
                self.disconnect(other_id)

    async def send_online_snapshot(self, new_user_id: str, websocket: WebSocket) -> None:
        """Tell a freshly-connected user which other users are already online."""
        for other_id in list(self.active_connections.keys()):
            if other_id == new_user_id:
                continue
            try:
                await websocket.send_text(json.dumps({
                    "type": "online",
                    "sender_id": other_id,
                    "timestamp": now_iso(),
                }))
            except Exception:
                logger.exception("Failed sending online snapshot for %s to %s", other_id, new_user_id)


manager = ConnectionManager()


@app.get("/")
@app.get("/health")
async def health_check():
    return {
        "status": "ok",
        "service": "chat-backend",
        "online_users": list(manager.active_connections.keys()),
    }


@app.get("/messages/{user_a}/{user_b}")
async def get_message_history(user_a: str, user_b: str, limit: int = 200):
    """Returns the full saved history between two users, oldest first.
    Used by the Flutter client when a chat screen is opened, so history
    survives app restarts and backend restarts."""
    chat_id = chat_id_for(user_a, user_b)
    messages = await fetch_history(chat_id, limit=limit)
    return {"chat_id": chat_id, "messages": messages}


@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(user_id, websocket)
    await manager.send_online_snapshot(user_id, websocket)
    await manager.broadcast_presence(user_id, "online")

    try:
        while True:
            raw = await websocket.receive_text()
            await handle_incoming(user_id, raw)

    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("Unexpected error on connection for %s", user_id)
    finally:
        manager.disconnect(user_id)
        await manager.broadcast_presence(user_id, "offline")


async def handle_incoming(sender_id: str, raw: str) -> None:
    """Parse and route one incoming WebSocket text frame."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        logger.warning("Ignoring non-JSON frame from %s: %r", sender_id, raw[:200])
        return

    msg_type = data.get("type")

    if msg_type == "message":
        await handle_chat_message(sender_id, data)
    elif msg_type == "typing":
        await handle_typing(sender_id, data)
    elif msg_type == "seen":
        await handle_status_update(sender_id, data, "seen")
    elif msg_type == "delivered":
        await handle_status_update(sender_id, data, "delivered")
    else:
        logger.warning("Unknown message type from %s: %s", sender_id, msg_type)


async def handle_chat_message(sender_id: str, data: dict) -> None:
    receiver_id: Optional[str] = data.get("receiver_id")
    if not receiver_id:
        return

    message_id = data.get("id") or f"msg_{now_iso()}"
    chat_id = data.get("chat_id") or chat_id_for(sender_id, receiver_id)
    text = data.get("message", "")
    timestamp = data.get("timestamp") or now_iso()
    status = "delivered" if manager.is_online(receiver_id) else "sent"

    # Persist immediately, so the message survives a backend restart
    # even if the receiver never comes online to receive it live.
    await save_message(message_id, chat_id, sender_id, receiver_id, text, timestamp, status)

    delivered = await manager.send_to_user(
        receiver_id,
        {
            "type": "message",
            "id": message_id,
            "chat_id": chat_id,
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "message": text,
            "timestamp": timestamp,
            "status": status,
        },
    )

    # Ack back to the sender so their UI can flip "sending" -> "sent"/"delivered".
    await manager.send_to_user(
        sender_id,
        {
            "type": "delivered" if delivered else "sent",
            "id": message_id,
            "chat_id": chat_id,
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "timestamp": now_iso(),
        },
    )


async def handle_typing(sender_id: str, data: dict) -> None:
    receiver_id: Optional[str] = data.get("receiver_id")
    if not receiver_id:
        return
    await manager.send_to_user(
        receiver_id,
        {
            "type": "typing",
            "chat_id": data.get("chat_id"),
            "sender_id": sender_id,
            "is_typing": data.get("is_typing", True),
            "timestamp": now_iso(),
        },
    )


async def handle_status_update(sender_id: str, data: dict, status: str) -> None:
    """Forward a 'seen' or 'delivered' receipt to the original sender,
    and persist the updated status against the saved message."""
    receiver_id: Optional[str] = data.get("receiver_id")
    if not receiver_id:
        return

    message_id = data.get("id")
    if message_id:
        await update_message_status(message_id, status)

    await manager.send_to_user(
        receiver_id,
        {
            "type": status,
            "id": data.get("id"),
            "chat_id": data.get("chat_id"),
            "sender_id": sender_id,
            "timestamp": now_iso(),
        },
    )
