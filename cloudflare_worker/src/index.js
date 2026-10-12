/**
 * Cloudflare Worker for Real-Time 1-to-1 Chat Demo
 * Stateful WebSockets with built-in SQLite persistence powered by Durable Objects.
 */

function nowIso() {
  return new Date().toISOString();
}

function chatIdFor(userA, userB) {
  const ids = [userA, userB].sort();
  return `chat_${ids[0]}_${ids[1]}`;
}

export class ChatServer {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.activeConnections = new Map(); // userId -> WebSocket

    // Initialize built-in SQLite database in Durable Object
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
    `);
  }

  isOnline(userId) {
    return this.activeConnections.has(userId);
  }

  saveMessage(id, chatId, senderId, receiverId, message, timestamp, status) {
    this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO messages (id, chat_id, sender_id, receiver_id, message, timestamp, status)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      id, chatId, senderId, receiverId, message, timestamp, status
    );
  }

  updateMessageStatus(id, status) {
    this.ctx.storage.sql.exec(
      `UPDATE messages SET status = ? WHERE id = ?`,
      status, id
    );
  }

  fetchHistory(chatId, limit = 200) {
    const cursor = this.ctx.storage.sql.exec(
      `SELECT id, chat_id, sender_id, receiver_id, message, timestamp, status
       FROM messages WHERE chat_id = ? ORDER BY timestamp ASC LIMIT ?`,
      chatId, limit
    );
    return cursor.toArray();
  }

  sendToUser(userId, payload) {
    const ws = this.activeConnections.get(userId);
    if (!ws) return false;
    try {
      ws.send(JSON.stringify(payload));
      return true;
    } catch {
      this.activeConnections.delete(userId);
      return false;
    }
  }

  broadcastPresence(userId, status) {
    const payload = {
      type: status, // "online" | "offline"
      sender_id: userId,
      timestamp: nowIso(),
    };
    for (const [otherId, ws] of this.activeConnections.entries()) {
      if (otherId === userId) continue;
      try {
        ws.send(JSON.stringify(payload));
      } catch {
        this.activeConnections.delete(otherId);
      }
    }
  }

  sendOnlineSnapshot(newUserId, ws) {
    for (const otherId of this.activeConnections.keys()) {
      if (otherId === newUserId) continue;
      try {
        ws.send(JSON.stringify({
          type: "online",
          sender_id: otherId,
          timestamp: nowIso(),
        }));
      } catch {
        // ignore
      }
    }
  }

  async handleIncoming(senderId, raw) {
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return;
    }

    const type = data.type;
    const receiverId = data.receiver_id;
    if (!receiverId) return;

    if (type === "message") {
      const messageId = data.id || `msg_${nowIso()}`;
      const chatId = data.chat_id || chatIdFor(senderId, receiverId);
      const text = data.message || "";
      const timestamp = data.timestamp || nowIso();
      const status = this.isOnline(receiverId) ? "delivered" : "sent";

      // Persist immediately in SQLite
      this.saveMessage(messageId, chatId, senderId, receiverId, text, timestamp, status);

      // Forward to receiver
      const delivered = this.sendToUser(receiverId, {
        type: "message",
        id: messageId,
        chat_id: chatId,
        sender_id: senderId,
        receiver_id: receiverId,
        message: text,
        timestamp: timestamp,
        status: status,
      });

      // Ack to sender
      this.sendToUser(senderId, {
        type: delivered ? "delivered" : "sent",
        id: messageId,
        chat_id: chatId,
        sender_id: senderId,
        receiver_id: receiverId,
        timestamp: nowIso(),
      });
    } else if (type === "typing") {
      this.sendToUser(receiverId, {
        type: "typing",
        chat_id: data.chat_id,
        sender_id: senderId,
        is_typing: data.is_typing ?? true,
        timestamp: nowIso(),
      });
    } else if (type === "seen" || type === "delivered") {
      if (data.id) {
        this.updateMessageStatus(data.id, type);
      }
      this.sendToUser(receiverId, {
        type: type,
        id: data.id,
        chat_id: data.chat_id,
        sender_id: senderId,
        timestamp: nowIso(),
      });
    }
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS Headers
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "*",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // Health / Root check
    if (path === "/" || path === "/health") {
      return new Response(
        JSON.stringify({
          status: "ok",
          service: "chat-backend-cloudflare-worker",
          online_users: Array.from(this.activeConnections.keys()),
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // History REST endpoint: /messages/:user_a/:user_b
    const messagesMatch = path.match(/^\/messages\/([^/]+)\/([^/]+)/);
    if (messagesMatch) {
      const userA = messagesMatch[1];
      const userB = messagesMatch[2];
      const chatId = chatIdFor(userA, userB);
      const messages = this.fetchHistory(chatId);
      return new Response(
        JSON.stringify({ chat_id: chatId, messages: messages }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // WebSocket endpoint: /ws/:user_id
    const wsMatch = path.match(/^\/ws\/([^/]+)/);
    if (wsMatch) {
      if (request.headers.get("Upgrade") !== "websocket") {
        return new Response("Expected WebSocket", { status: 426 });
      }

      const userId = wsMatch[1];
      const webSocketPair = new WebSocketPair();
      const [client, server] = Object.values(webSocketPair);

      server.accept();
      this.activeConnections.set(userId, server);

      // Send online snapshot of existing users and broadcast presence
      this.sendOnlineSnapshot(userId, server);
      this.broadcastPresence(userId, "online");

      server.addEventListener("message", async (event) => {
        try {
          await this.handleIncoming(userId, event.data);
        } catch (err) {
          console.error("Error handling incoming message", err);
        }
      });

      const cleanup = () => {
        if (this.activeConnections.get(userId) === server) {
          this.activeConnections.delete(userId);
          this.broadcastPresence(userId, "offline");
        }
      };

      server.addEventListener("close", cleanup);
      server.addEventListener("error", cleanup);

      return new Response(null, {
        status: 101,
        webSocket: client,
      });
    }

    return new Response("Not Found", { status: 404, headers: corsHeaders });
  }
}

export default {
  async fetch(request, env) {
    // Single shared global Durable Object instance for all chat routing
    const id = env.CHAT_SERVER.idFromName("global-chat");
    const obj = env.CHAT_SERVER.get(id);
    return obj.fetch(request);
  },
};

