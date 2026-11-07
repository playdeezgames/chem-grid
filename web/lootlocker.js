// SPLORR!! LootLocker shim, version 1 (November 7, 2026). Source of truth: the bok-of-splorr vault,
// splorr/Tech/lootlocker/. Copy it into a game's web/ folder unchanged; per-game settings go in the page.
// How to use it: splorr/Tech/LootLocker.md.
//
// Talks to LootLocker's Game API from the browser: guest sign-in, player name, leaderboards, player storage
// and server time. The key is a game's public client key, not a secret. Every host that serves the page must
// be on the LootLocker game's CORS Allowlist (GitHub Pages: https://playdeezgames.github.io; itch.io:
// https://html-classic.itch.zone). Nothing here is cheat-proof: whatever the client sends is trusted.
//
//   const ll = LootLocker({ domain, key, version, idKey });
//   ll.setName("DR WHO");                       // renamed on the server with the next call
//   const rows = await ll.list("board_key", 10); // [{ rank, score, name, metadata, mine }]
//   await ll.submit("board_key", 1540, "optional metadata");
//   await ll.storageSet("save", json); const v = await ll.storageGet("save"); // null when missing
//   const when = await ll.serverTime();          // a Date, from LootLocker's clock
//
// For an Odin game, ll.odinImports(memory) gives the "lootlocker" import namespace that the shared Odin
// package (lootlocker.odin) expects; pass it to odin.runWasm next to the game's own namespace.
"use strict";

function LootLocker(cfg) {
  const domain = cfg.domain || "";
  const key = cfg.key || "";
  const version = cfg.version || "1.0.0";
  const nameMax = cfg.nameMax || 16;

  // localStorage that may be missing (private windows, blocked storage): fall back to memory.
  const mem = new Map();
  const store = {
    get: (k) => { try { const v = localStorage.getItem(k); return v === null ? mem.get(k) ?? null : v; } catch (e) { return mem.get(k) ?? null; } },
    set: (k, v) => { mem.set(k, v); try { localStorage.setItem(k, v); } catch (e) {} },
  };

  // The anonymous id LootLocker's guest login keys the player on. Whoever knows it is that player, so it
  // doubles as a transfer code: show it only on request and treat it as a secret. itch.io serves every
  // developer's HTML games from one origin, so idKey must be namespaced (e.g. "splorr-ll-player").
  const idKey = cfg.idKey || "splorr-ll-player";
  const newId = () => Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("");
  let playerId = store.get(idKey);
  if (!playerId) { playerId = newId(); store.set(idKey, playerId); }

  let playerName = "";
  let session = null, pending = null, serverName = null;

  const call = async (method, path, token, body) => {
    const headers = { "Content-Type": "application/json" };
    if (token) headers["x-session-token"] = token;
    const r = await fetch(domain + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    if (!r.ok) {
      let why = "";
      try { why = (await r.json()).message || ""; } catch (e) {}
      throw new Error(method + " " + path + " " + r.status + (why ? ": " + why : ""));
    }
    return r.status === 204 ? null : r.json();
  };

  const signIn = () => {
    if (!domain || !key) return Promise.reject(new Error("LootLocker not configured"));
    if (session) return Promise.resolve(session);
    if (!pending) {
      pending = (async () => {
        const s = await call("POST", "/game/v2/session/guest", null, {
          // development_mode no longer selects different data (Stage and Live were retired); sent as JetLag does.
          game_key: key, game_version: version, development_mode: true, player_identifier: playerId,
        });
        session = { token: s.session_token, player: String(s.player_id), uid: s.public_uid };
        serverName = s.player_name || "";
        return session;
      })().finally(() => { pending = null; });
    }
    return pending;
  };

  // Runs fn with a session whose name is up to date. Tokens expire, so one failure signs in again and retries.
  const withSession = async (fn) => {
    const run = async () => {
      const s = await signIn();
      if (playerName && serverName !== playerName) {
        await call("PATCH", "/game/player/name", s.token, { name: playerName });
        serverName = playerName;
      }
      return fn(s);
    };
    try { return await run(); } catch (e) { session = null; return run(); }
  };

  const cleanName = (text) => String(text).replace(/[^\x20-\x7e]/g, "?").slice(0, nameMax);
  const enc = encodeURIComponent;

  const api = {
    get playerId() { return playerId; },
    // Adopt a transfer code typed on another device: this browser becomes that player from the next call.
    adoptPlayerId(code) {
      const c = String(code).trim().toLowerCase();
      if (!/^[0-9a-f]{24}$/.test(c)) return false;
      playerId = c; store.set(idKey, c); session = null; serverName = null;
      return true;
    },
    setName(name) { playerName = cleanName(name); },
    signIn,

    // Top `count` rows of a board, best first. `mine` marks this player's row.
    async list(board, count = 10) {
      return withSession(async (s) => {
        const r = await call("GET", "/game/leaderboards/" + enc(board) + "/list?count=" + count, s.token);
        return (r.items || []).map((row) => ({
          rank: row.rank,
          score: Math.max(0, Math.min(Number(row.score) || 0, 2147483647)),
          name: cleanName((row.player && (row.player.name || row.player.public_uid)) || "?"),
          metadata: row.metadata || "",
          mine: String(row.member_id) === s.player || (row.player && String(row.player.id) === s.player),
        }));
      });
    },
    // This player's own entry on a board, or null when they have none.
    async mine(board) {
      return withSession(async (s) => {
        const r = await call("GET", "/game/leaderboards/" + enc(board) + "/member/" + enc(s.player), s.token);
        return r && r.rank ? { rank: r.rank, score: Number(r.score) || 0, metadata: r.metadata || "" } : null;
      });
    },
    async submit(board, score, metadata) {
      return withSession((s) => {
        const body = { member_id: s.player, score: Math.max(0, Math.floor(score)) };
        if (metadata) body.metadata = String(metadata);
        return call("POST", "/game/leaderboards/" + enc(board) + "/submit", s.token, body);
      });
    },

    // Player storage: keys up to 60 characters, values up to 1,500. A public value is readable by anyone.
    // An empty value counts as missing (see storageDelete).
    async storageGet(k) {
      return withSession(async (s) => {
        const r = await call("GET", "/game/v1/player/storage?key=" + enc(k), s.token);
        const p = r && r.payload;
        const item = Array.isArray(p) ? p.find((x) => x.key === k) : p;
        return item && item.key === k && item.value !== "" ? item.value : null;
      });
    },
    async storageSet(k, value, isPublic = false) {
      return withSession((s) => call("POST", "/game/v1/player/storage", s.token,
        { payload: [{ key: k, value: String(value), is_public: !!isPublic, order: 1 }] }));
    },
    // Writes an empty value instead of calling DELETE: after a DELETE (which answers 200) reads kept returning
    // the old value for seconds or more, while overwrites read back at once (tested November 7, 2026).
    async storageDelete(k) {
      return api.storageSet(k, "");
    },

    // LootLocker's clock, so a daily seed is the same for every player whatever their own clock says.
    async serverTime() {
      return withSession(async (s) => new Date((await call("GET", "/game/ping", s.token)).date));
    },

    // The "lootlocker" import namespace for the shared Odin package. Results come back through its exports.
    // boardFor maps the key the game asks for to the real board (e.g. to a test board on ?board=test).
    odinImports(memory, boardFor = (k) => k) {
      const ex = () => memory.exports;
      const putName = (text) => {
        const bytes = new Uint8Array(memory.memory.buffer, ex().lootlocker_scratch(), nameMax);
        const n = Math.min(text.length, nameMax);
        for (let i = 0; i < n; i++) bytes[i] = text.charCodeAt(i);
        return n;
      };
      return {
        ll_name: (ptr, len) => { api.setName(memory.loadString(ptr, len)); },
        ll_refresh: (ptr, len, count) => {
          api.list(boardFor(memory.loadString(ptr, len)), count).then((rows) => {
            ex().lootlocker_begin();
            for (const r of rows) ex().lootlocker_add(r.score, putName(r.name), r.mine ? 1 : 0);
            ex().lootlocker_status(1);
          }).catch(() => ex().lootlocker_status(0));
        },
        ll_submit: (ptr, len, score) => {
          api.submit(boardFor(memory.loadString(ptr, len)), score).then(() => ex().lootlocker_sent(1), () => ex().lootlocker_sent(0));
        },
      };
    },
  };
  return api;
}
