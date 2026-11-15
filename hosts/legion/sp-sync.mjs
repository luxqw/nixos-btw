// sp-sync: work records <-> Super Productivity <-> T3 threads.
// Deterministic, no LLM. Run by a systemd user timer (see home.nix); `--dry-run`
// prints the planned changes and writes nothing (it only mints a short-lived
// read-only T3 session to read thread state).
//
// SP: local REST API on 127.0.0.1:3876 (it can list projects and tags but not
// create them; missing tags are made through SP's short syntax, see main()).
// T3: read = GET /api/orchestration/threads/:id/bounded (projection.thread.archivedAt / settledAt; either means closed),
// write = WebSocket RPC `orchestration.dispatchCommand` {type: "thread.archive"},
// both with a short-lived bearer session issued by the local `t3 auth session issue`.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import {execFile} from "node:child_process";
import {pathToFileURL} from "node:url";

const HOME = os.homedir();
const argv = process.argv.slice(2);
const DRY = argv.includes("--dry-run");
const VERBOSE = DRY || argv.includes("--verbose");

const SP_ORIGIN = process.env.SP_SYNC_SP_ORIGIN || "http://127.0.0.1:3876";
const SP_TOKEN_FILE = path.join(HOME, ".config/superProductivity/local-rest-api-token");
const T3_DIR = path.join(HOME, ".t3");
const T3_BIN = process.env.SP_SYNC_T3 || path.join(T3_DIR, "bin/t3");
const STATE_FILE = path.join(process.env.XDG_STATE_HOME || path.join(HOME, ".local/state"), "sp-sync/state.json");

// Roots: SP_SYNC_ROOTS="path=project;path=project" overrides the defaults (an empty
// project means the SP Inbox). A project that does not exist in SP means Inbox plus a
// hint; the task moves once the project exists.
const ROOTS = (process.env.SP_SYNC_ROOTS
  ? process.env.SP_SYNC_ROOTS.split(";").map((s) => s.split("="))
  : [
      [path.join(HOME, "Documents/projects/vpn/.scratch"), "vpn"],
      ["/etc/nixos/.scratch", "nixos"],
      [path.join(HOME, ".agents/handoffs"), "agents"],
    ]
).map(([p, project]) => ({path: p, project}));

const TAG_WAITING = "waiting-on-me";
const TAG_ACTIVE = "in-progress";
const TAG_PARTIAL = "partial";
const OUR_TAGS = [TAG_WAITING, TAG_ACTIVE, TAG_PARTIAL];
const STATES = ["active", "waiting-owner", "partially-applied", "done"];
// Line 3: the state word, then nothing, or whitespace / "(" / a dash or colon and free text.
const STATE_LINE = /^Work state:\s*(active|waiting-owner|partially-applied|done)(?=$|[\s(\-\u2013\u2014:,;.])\s*(.*)$/;
const NOTES_BEGIN = "<!-- sp-sync:begin -->";
const NOTES_END = "<!-- sp-sync:end -->";

const secrets = new Set();
const redact = (s) => {
  let out = String(s);
  for (const x of secrets) out = out.split(x).join("<redacted>");
  return out;
};
const log = (msg) => console.log(`sp-sync: ${redact(msg)}`);
const plan = (msg) => console.log(`sp-sync: ${DRY ? "plan: " : ""}${redact(msg)}`);
const vlog = (msg) => VERBOSE && log(msg);
const today = () => {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
};

// ---------- records ----------

function parseLine3(line) {
  const m = STATE_LINE.exec((line ?? "").replace(/\r$/, ""));
  if (!m) return null;
  let note = m[2].trim();
  const paren = /^\((.*)\)$/.exec(note);
  note = paren ? paren[1].trim() : note.replace(/^[-\u2013\u2014:,;.]\s*/, "").trim();
  return {state: m[1], note};
}

export function parseRecord(file, text) {
  if (text === undefined) {
    try {
      text = fs.readFileSync(file, "utf8");
    } catch {
      return null;
    }
  }
  const lines = text.split("\n");
  const m = parseLine3(lines[2]);
  if (!m) return null;
  const head = lines.slice(0, 14);
  const titleLine = lines.find((l) => l.startsWith("# "));
  const threadLine = head.find((l) => l.startsWith("Thread:"));
  return {
    file,
    state: m.state,
    note: m.note,
    title: titleLine ? titleLine.slice(2).trim() : path.basename(file, ".md"),
    thread: threadLine ? parseThread(threadLine.slice(7)) : null,
    next: nextAction(lines, head, m.note),
    mtime: fs.statSync(file).mtimeMs,
  };
}

function parseThread(raw) {
  const v2 = /t3-thread:\/\/v2\/([0-9a-f-]{36})\/([^\s<>)`"']+)/.exec(raw);
  if (v2) return {env: v2[1], id: decodeURIComponent(v2[2]), link: `t3-thread://v2/${v2[1]}/${v2[2]}`};
  const bare = /^\s*`?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})`?/.exec(raw);
  if (bare) return {env: null, id: bare[1], link: bare[1]};
  return raw.trim() ? {env: null, id: null, link: raw.trim().slice(0, 200)} : null;
}

function nextAction(lines, head, note) {
  const clean = (s) => s.replace(/\s+/g, " ").trim().slice(0, 400);
  const nextHdr = head.find((l) => /^Next:/i.test(l));
  if (nextHdr) return clean(nextHdr.replace(/^Next:/i, ""));
  const start = lines.findIndex((l) => /^##\s+Current state/i.test(l));
  if (start >= 0) {
    let end = lines.findIndex((l, i) => i > start && /^##\s/.test(l));
    if (end < 0) end = lines.length;
    const section = lines.slice(start + 1, end);
    const bullet = (re) => section.find((l) => /^\s*[-*]\s/.test(l) && re.test(l.replace(/^\s*[-*]\s*/, "")));
    const hit = bullet(/^\**next\b/i) || bullet(/\bnext action\b/i) || bullet(/\bnext\b/i);
    if (hit) return clean(hit.replace(/^\s*[-*]\s*/, ""));
  }
  return clean(note);
}

function ownerIsNext(rec) {
  return /\bowner\b/i.test(rec.next);
}

// One work unit per record file: a .md file directly in a root or one directory below it
// whose line 3 parses. A file whose line 3 does not parse is "unparsed" (ignored, but its
// task, if any, is left alone).
function scanRoots() {
  const units = [];
  const okRoots = new Set();
  const addFile = (file, root) => {
    const rec = parseRecord(file);
    if (rec) units.push({key: file, root, rec});
  };
  for (const root of ROOTS) {
    let entries;
    try {
      entries = fs.readdirSync(root.path, {withFileTypes: true});
    } catch (e) {
      log(`root ${root.path} unreadable (${e.code}); skipped`);
      continue;
    }
    okRoots.add(root.path);
    for (const ent of entries) {
      const full = path.join(root.path, ent.name);
      try {
        if (ent.isFile() && ent.name.endsWith(".md")) addFile(full, root);
        else if (ent.isDirectory()) {
          for (const f of fs.readdirSync(full, {withFileTypes: true})) {
            if (f.isFile() && f.name.endsWith(".md")) addFile(path.join(full, f.name), root);
          }
        }
      } catch (e) {
        log(`scan ${full}: ${e.message}`);
      }
    }
  }
  return {units, okRoots};
}

// Rewrites only line 3 (atomic: temp file + rename, mode preserved), compare-and-swap:
// the file is re-read and re-parsed, and must still have the state and the Thread: it had
// when sp-sync read it ("changed" otherwise: skipped until the next run).
// Returns "closed", "done" (already done) or "changed" (also when the file is gone).
export function closeRecord(rec, reason) {
  let text;
  try {
    text = fs.readFileSync(rec.file, "utf8");
  } catch {
    return "changed";
  }
  const fresh = parseRecord(rec.file, text);
  if (!fresh || fresh.state !== rec.state || (fresh.thread?.link ?? null) !== (rec.thread?.link ?? null)) return "changed";
  if (fresh.state === "done") return "done";
  const lines = text.split("\n");
  lines[2] = `Work state: done (${reason}, ${today()})${lines[2].endsWith("\r") ? "\r" : ""}`;
  const tmp = path.join(path.dirname(rec.file), `.${path.basename(rec.file)}.sp-sync-${process.pid}.tmp`);
  fs.writeFileSync(tmp, lines.join("\n"), {mode: fs.statSync(rec.file).mode & 0o7777});
  fs.renameSync(tmp, rec.file);
  return "closed";
}

// ---------- Super Productivity ----------

class SP {
  constructor(token) {
    this.token = token;
  }
  async req(method, p, body) {
    const r = await fetch(SP_ORIGIN + p, {
      method,
      headers: {authorization: `Bearer ${this.token}`, "content-type": "application/json"},
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
    const text = await r.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      /* not JSON */
    }
    if (!r.ok || !json?.ok) {
      const err = new Error(`SP ${method} ${p.split("?")[0]} -> ${r.status} ${text.slice(0, 200)}`);
      err.status = r.status;
      throw err;
    }
    return json.data;
  }
}

const markerOf = (notes) => /^sp-sync: (\/.+)$/m.exec(notes ?? "")?.[1]?.trim() ?? null;

// The managed block sits between explicit markers; the owner's text above and below
// survives. Legacy notes (no begin marker): everything up to the `sp-sync:` line is managed.
function splitNotes(existing) {
  const b = existing.indexOf(NOTES_BEGIN);
  if (b >= 0) {
    const e = existing.indexOf(NOTES_END, b);
    if (e >= 0) return {head: existing.slice(0, b), tail: existing.slice(e + NOTES_END.length)};
    // End marker missing: only the consecutive managed lines after the begin marker are replaced.
    const lines = existing.slice(b + NOTES_BEGIN.length).split("\n");
    let i = 1;
    while (i < lines.length && /^(state|next|thread|record|sp-sync): /.test(lines[i])) i++;
    return {head: existing.slice(0, b), tail: lines.slice(i).join("\n").replace(/^(?=.)/, "\n")};
  }
  const m = /^sp-sync: \/.+$/m.exec(existing);
  return m ? {head: "", tail: existing.slice(m.index + m[0].length)} : {head: `${existing}\n\n`, tail: ""};
}

export function buildNotes(rec, existing) {
  const managed = [`state: ${rec.state}${rec.note ? ` (${rec.note.replace(/\s+/g, " ").slice(0, 200)})` : ""}`];
  if (rec.next) managed.push(`next: ${rec.next}`);
  if (rec.thread) managed.push(`thread: ${rec.thread.link}`);
  managed.push(`record: ${rec.file}`, `sp-sync: ${rec.file}`);
  const block = `${NOTES_BEGIN}\n${managed.join("\n")}\n${NOTES_END}`;
  if (!existing) return block;
  const {head, tail} = splitNotes(existing);
  // A "record deleted" note is stale once the record is back.
  return head + block + tail.replace(/\n*^sp-sync: record deleted .*$/gm, "");
}

// ---------- T3 ----------

const cleanEnv = () => Object.fromEntries(Object.entries(process.env).filter(([k]) => k !== "ELECTRON_RUN_AS_NODE"));

class T3 {
  // write=false (dry run): the session only gets the orchestration:read scope.
  constructor({write}) {
    this.write = write;
    this.session = null;
    this.unavailable = null;
    this.cache = new Map();
    this.envId = null;
  }
  async init() {
    if (this.session || this.unavailable) return;
    try {
      const rt = JSON.parse(fs.readFileSync(path.join(T3_DIR, "userdata/server-runtime.json"), "utf8"));
      this.origin = rt.origin;
      this.envId = fs.readFileSync(path.join(T3_DIR, "userdata/environment-id"), "utf8").trim();
      const out = await new Promise((resolve, reject) =>
        execFile(
          T3_BIN,
          ["auth", "session", "issue", "--json", "--ttl", "5m", "--label", "sp-sync", "--scope", "orchestration:read", ...(this.write ? ["--scope", "orchestration:operate"] : [])],
          {timeout: 30000, env: cleanEnv()},
          (err, stdout, stderr) => {
            if (!err) return resolve(stdout);
            const why = String(stderr || "").trim().split("\n")[0].slice(0, 160);
            reject(new Error(`t3 auth session issue failed: exit ${err.code ?? err.signal ?? "?"}${why ? `: ${why}` : ""}`));
          },
        ),
      );
      const s = JSON.parse(out.trim());
      secrets.add(s.token);
      this.session = s;
    } catch (e) {
      this.unavailable = e.message;
      log(`T3 unavailable (${e.message}); thread checks skipped`);
    }
  }
  // Idempotent: revokes the session once, from the normal path, finally or a signal handler.
  async close() {
    const s = this.session;
    if (!s || this.closing) return this.closing;
    this.closing = new Promise((resolve) =>
      execFile(T3_BIN, ["auth", "session", "revoke", s.sessionId], {timeout: 30000, env: cleanEnv()}, () => resolve()),
    );
    return this.closing;
  }
  headers() {
    return {authorization: `Bearer ${this.session.token}`, "x-t3-orchestration-protocol": "2", accept: "application/json"};
  }
  // true = archived, false = active, null = unknown (not ours, missing, server down)
  // fresh=true bypasses the per-run cache.
  async archived(th, {fresh = false} = {}) {
    if (!th?.id) return null;
    if (th.env && th.env !== (await this.localEnv())) return null;
    if (!fresh && this.cache.has(th.id)) return this.cache.get(th.id);
    await this.init();
    if (this.unavailable) return null;
    let value = null;
    try {
      const url = `${this.origin}/api/orchestration/threads/${encodeURIComponent(th.id)}/bounded?deferWork=1&compactTurnItems=1&dedupeBodies=1&compactIds=1`;
      const r = await fetch(url, {headers: this.headers(), signal: AbortSignal.timeout(30000)});
      if (r.status === 404) vlog(`T3 thread ${th.id.slice(0, 24)} not found`);
      else if (!r.ok) log(`T3 thread read ${th.id.slice(0, 24)} -> ${r.status}`);
      else {
        const j = await r.json();
        const t = j?.projection?.thread;
        if (t && "archivedAt" in t) value = Boolean(t.archivedAt || t.settledAt); // archived or settled = closed
      }
    } catch (e) {
      log(`T3 thread read ${th.id.slice(0, 24)}: ${e.message}`);
    }
    this.cache.set(th.id, value);
    return value;
  }
  async localEnv() {
    if (this.envId) return this.envId;
    try {
      this.envId = fs.readFileSync(path.join(T3_DIR, "userdata/environment-id"), "utf8").trim();
    } catch {
      /* unknown */
    }
    return this.envId;
  }
  async archive(th) {
    if (!this.write) throw new Error("read-only T3 session");
    await this.init();
    if (this.unavailable) throw new Error("T3 unavailable");
    const tr = await fetch(this.origin + "/api/auth/websocket-ticket", {method: "POST", headers: this.headers(), signal: AbortSignal.timeout(15000)});
    if (!tr.ok) throw new Error(`websocket ticket -> ${tr.status}`);
    const {ticket} = await tr.json();
    secrets.add(ticket);
    const wsUrl = this.origin.replace(/^http/, "ws") + `/ws?wsTicket=${encodeURIComponent(ticket)}&orchestrationProtocol=2`;
    await new Promise((resolve, reject) => {
      const ws = new WebSocket(wsUrl);
      const timer = setTimeout(() => {
        ws.close();
        reject(new Error("archive timed out"));
      }, 20000);
      const done = (fn, v) => {
        clearTimeout(timer);
        try {
          ws.close();
        } catch {
          /* already closed */
        }
        fn(v);
      };
      ws.onopen = () =>
        ws.send(
          JSON.stringify({
            _tag: "Request",
            id: "1",
            tag: "orchestration.dispatchCommand",
            payload: {type: "thread.archive", commandId: crypto.randomUUID(), threadId: th.id},
            headers: [],
            traceId: "0".repeat(32),
            spanId: "0".repeat(16),
            sampled: false,
          }),
        );
      ws.onmessage = (e) => {
        let m;
        try {
          m = JSON.parse(String(e.data));
        } catch {
          return;
        }
        if (m._tag !== "Exit") return;
        if (m.exit?._tag === "Success") done(resolve);
        else done(reject, new Error(`archive rejected: ${JSON.stringify(m.exit).slice(0, 200)}`));
      };
      ws.onerror = () => done(reject, new Error("websocket error"));
    });
    this.cache.set(th.id, true);
  }
}

// ---------- state ----------

function loadState() {
  try {
    return {state: JSON.parse(fs.readFileSync(STATE_FILE, "utf8")), first: false};
  } catch {
    return {state: {version: 1, units: {}}, first: !fs.existsSync(STATE_FILE)};
  }
}
function saveState(state) {
  fs.mkdirSync(path.dirname(STATE_FILE), {recursive: true});
  const tmp = `${STATE_FILE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(state, null, 1), {mode: 0o600});
  fs.renameSync(tmp, STATE_FILE);
}


// ---------- lock, cleanup ----------

const cleanups = [];
let shuttingDown = false;
async function runCleanups() {
  for (const fn of cleanups.splice(0).reverse()) {
    try {
      await fn();
    } catch {
      /* best effort */
    }
  }
}
// SIGTERM/SIGINT: revoke the T3 session, then exit. (Overlapping runs are prevented by
// flock in the wrapper, see home.nix.)
function installSignalHandlers() {
  for (const [sig, code] of [["SIGTERM", 143], ["SIGINT", 130]]) {
    process.on(sig, async () => {
      if (shuttingDown) return;
      shuttingDown = true;
      log(`${sig}: cleaning up`);
      await runCleanups();
      process.exit(code);
    });
  }
}

// ---------- main ----------

// A record file is "missing" only when stat says ENOENT; any other error counts as present.
function fileMissing(file) {
  try {
    fs.statSync(file);
    return false;
  } catch (e) {
    return e.code === "ENOENT" || e.code === "ENOTDIR";
  }
}

async function main() {
  // SP not running (or REST API off) is the only reason to exit 0 early.
  let health;
  try {
    const r = await fetch(SP_ORIGIN + "/health", {signal: AbortSignal.timeout(5000)});
    health = await r.json().catch(() => ({}));
  } catch {
    log(`SP REST API not reachable on ${SP_ORIGIN.replace(/^https?:\/\//, "")}: SP is not running, or Settings > Misc > Local REST API is off; nothing to do`);
    return 0;
  }
  if (health?.data?.rendererReady === false) {
    log("SP is still loading; nothing to do");
    return 0;
  }
  let token;
  try {
    token = fs.readFileSync(SP_TOKEN_FILE, "utf8").trim();
    secrets.add(token);
  } catch {
    log(`SP answers but there is no token at ${SP_TOKEN_FILE}`);
    return 1;
  }
  const sp = new SP(token);
  const t3 = new T3({write: !DRY});
  cleanups.push(() => t3.close());
  try {
    return await sync(sp, t3);
  } finally {
    await runCleanups();
  }
}

async function sync(sp, t3) {
  const {state, first} = loadState();
  if (first) log("first run (no state yet): creating and updating SP tasks only, no closures applied");

  const [projects, firstTags] = await Promise.all([sp.req("GET", "/projects"), sp.req("GET", "/tags")]);
  let tags = firstTags;
  // The REST API cannot create tags, but SP's short syntax does ("#name" in a task title,
  // applied a moment later): a throwaway task creates each missing tag, then is deleted.
  const missingTags = process.env.SP_SYNC_CREATE_TAGS === "0" ? [] : OUR_TAGS.filter((n) => !tags.some((t) => t.title === n));
  for (const name of missingTags) {
    plan(`create SP tag "${name}" (via a throwaway task with "#${name}")`);
    if (DRY) continue;
    try {
      const tmp = await sp.req("POST", "/tasks", {title: `sp-sync tag bootstrap #${name}`});
      for (let i = 0; i < 15 && !tags.some((t) => t.title === name); i++) {
        await new Promise((r) => setTimeout(r, 1000));
        tags = await sp.req("GET", "/tags");
      }
      await sp.req("DELETE", `/tasks/${tmp.id}`);
    } catch (e) {
      log(`creating tag "${name}" failed: ${e.message}`);
    }
  }
  const tasks = await sp.req("GET", "/tasks?source=all&includeDone=true");
  const projectId = (title) => projects.find((p) => p.title === title && !p.isArchived)?.id;
  const tagId = (title) => tags.find((t) => t.title === title)?.id;
  const warned = new Set();
  const warnOnce = (k, msg) => {
    if (!warned.has(k)) {
      warned.add(k);
      log(msg);
    }
  };

  const {units, okRoots} = scanRoots();
  const rootOf = (p) => ROOTS.find((r) => p === r.path || p.startsWith(r.path + path.sep));
  // One SP task per record file; the marker path is the key (an open task wins over a done duplicate).
  const tasksByKey = new Map();
  for (const t of tasks) {
    if (t.parentId) continue;
    const key = markerOf(t.notes);
    if (!key || !rootOf(key)) continue;
    const prev = tasksByKey.get(key);
    if (!prev || (prev.isDone && !t.isDone)) tasksByKey.set(key, t);
  }
  // Migration from the per-directory model: a state entry keyed by a directory moves, in place,
  // to the record file named in its task's marker (the file that was selected for the directory).
  // The task is kept as is (no closure, no duplicate); other record files of the directory get new tasks.
  for (const key of Object.keys(state.units)) {
    if (key.endsWith(".md")) continue;
    const st = state.units[key];
    const cands = [...tasksByKey.entries()].filter(([file, t]) => t.id === st.taskId || path.dirname(file) === key);
    const hit = cands.find(([, t]) => t.id === st.taskId) ?? cands.find(([, t]) => !t.isDone) ?? cands[0];
    delete state.units[key];
    if (hit && !state.units[hit[0]]) {
      state.units[hit[0]] = {...st, missing: 0};
      plan(`migrate state ${key} -> ${hit[0]}`);
    } else plan(`drop legacy state ${key}`);
  }

  const stats = {records: units.length, created: 0, updated: 0, closed: 0, spDone: 0, reopened: 0, errors: 0};
  const seenKeys = new Set();
  const markSpDone = async (task, st, body = {}) => {
    if (!DRY) {
      await sp.req("PATCH", `/tasks/${task.id}`, {isDone: true, ...body});
      st.closedBy = "sp-sync";
      st.seenOpen = false;
    }
    stats.spDone++;
  };
  for (const u of units) {
    seenKeys.add(u.key);
    const rec = u.rec;
    try {
      const st = (state.units[u.key] ||= {});
      st.missing = 0;
      let task = tasksByKey.get(u.key);
      // A done record is no longer a candidate for rule 3: after a reopen the thread must be seen active again.
      if (rec.state === "done") delete st.threadActive;
      const desiredTagNames = rec.state === "waiting-owner" ? [TAG_WAITING] : rec.state === "partially-applied" ? [TAG_PARTIAL] : rec.state === "active" ? [ownerIsNext(rec) ? TAG_WAITING : TAG_ACTIVE] : [];
      const desiredTagIds = desiredTagNames
        .map((n) => {
          const id = tagId(n);
          if (!id) warnOnce(`tag:${n}`, `SP tag "${n}" is missing and the REST API cannot create tags: create it in SP once`);
          return id;
        })
        .filter(Boolean);
      const projId = u.root.project ? projectId(u.root.project) : undefined;
      if (u.root.project && !projId) warnOnce(`proj:${u.root.project}`, `SP project "${u.root.project}" does not exist: its tasks stay in the Inbox until you create it in SP`);

      // Thread state (only for records that are not done).
      let threadArchived = null;
      if (rec.state !== "done" && rec.thread?.id) threadArchived = await t3.archived(rec.thread);
      if (threadArchived === false && rec.thread) st.threadActive = rec.thread.id;

      if (!task) {
        if (rec.state === "done") {
          vlog(`${rec.file}: done, no SP task; skipped`);
          continue;
        }
        const body = {
          title: rec.title,
          notes: buildNotes(rec),
          tagIds: desiredTagIds,
          projectId: projId ?? "INBOX_PROJECT",
          isIgnoreShortSyntax: true,
        };
        plan(`create SP task "${rec.title}" [${rec.state}] <- ${rec.file}`);
        if (!DRY) {
          const created = await sp.req("POST", "/tasks", body);
          st.taskId = created.id;
          st.seenOpen = true;
          st.closedBy = undefined;
          st.title = rec.title;
        }
        stats.created++;
        st.recState = rec.state;
        continue;
      }

      st.taskId = task.id;
      // 1. SP task marked done by the owner while the record is not done (never a task sp-sync closed itself).
      if (!first && task.isDone && st.seenOpen && st.closedBy !== "sp-sync" && rec.state !== "done") {
        plan(`close record ${rec.file}: SP task done -> line 3 "closed by owner in Super Productivity"`);
        if (!DRY) {
          const reason = "closed by owner in Super Productivity";
          const r = closeRecord(rec, reason);
          if (r === "changed") {
            log(`${rec.file} changed since it was read; closure retried next run`);
            continue;
          }
          stats.closed++;
          if (r === "closed" && rec.thread?.id && (await t3.archived(rec.thread)) === false) {
            plan(`archive T3 thread ${rec.thread.id.slice(0, 40)}`);
            await t3.archive(rec.thread).catch((e) => log(`archive thread failed: ${e.message}`));
          }
          st.recState = "done";
          st.seenOpen = false;
          st.closedBy = "owner";
          delete st.threadActive;
        } else {
          stats.closed++;
          if (rec.thread?.id && (await t3.archived(rec.thread)) === false) plan(`archive T3 thread ${rec.thread.id.slice(0, 40)}`);
        }
        continue;
      }
      // 2. Record done -> SP task done.
      if (rec.state === "done") {
        if (!task.isDone) {
          plan(`mark SP task done "${task.title}" (record done) <- ${rec.file}`);
          await markSpDone(task, st);
        }
        st.recState = "done";
        st.seenOpen = false;
        continue;
      }
      // 3. Current T3 thread archived by the owner while the record is not done.
      if (!first && threadArchived === true && st.threadActive === rec.thread.id) {
        plan(`close record ${rec.file}: T3 thread archived or settled -> line 3 "closed by owner: thread archived or settled in T3"`);
        if (!DRY) {
          // Re-parse the record and re-check T3 for the thread it names now; an agent may have switched Thread:.
          const fresh = parseRecord(rec.file);
          if (!fresh || fresh.state !== rec.state || fresh.thread?.link !== rec.thread.link || (await t3.archived(fresh.thread, {fresh: true})) !== true) {
            log(`${rec.file} or its thread changed since it was read; closure retried next run`);
            continue;
          }
          const reason = "closed by owner: thread archived or settled in T3";
          if (closeRecord(rec, reason) === "changed") {
            log(`${rec.file} changed since it was read; closure retried next run`);
            continue;
          }
          stats.closed++;
          if (!task.isDone) {
            plan(`mark SP task done "${task.title}" (thread archived)`);
            await markSpDone(task, st);
          }
          st.recState = "done";
          st.seenOpen = false;
          st.closedBy = "sp-sync";
          delete st.threadActive;
        } else {
          stats.closed++;
          if (!task.isDone) plan(`mark SP task done "${task.title}" (thread archived)`);
        }
        continue;
      }
      // 4. Record reopened (or back after a deletion) after sp-sync closed the task: reopen it.
      if (task.isDone && (st.recState === "done" || st.closedBy === "sp-sync")) {
        plan(`reopen SP task "${task.title}" (record is not done) <- ${rec.file}`);
        if (!DRY) {
          await sp.req("PATCH", `/tasks/${task.id}`, {isDone: false});
          st.closedBy = undefined;
        }
        stats.reopened++;
        task = {...task, isDone: false};
      }
      // 5. Keep an open task current.
      if (!task.isDone) {
        const changes = {};
        const notes = buildNotes(rec, task.notes);
        if (notes !== (task.notes ?? "")) changes.notes = notes;
        if (st.title !== rec.title && task.title !== rec.title) changes.title = rec.title;
        const ours = new Set(OUR_TAGS.map(tagId).filter(Boolean));
        const kept = (task.tagIds ?? []).filter((id) => !ours.has(id));
        const wantTags = [...kept, ...desiredTagIds];
        if (wantTags.length !== (task.tagIds ?? []).length || wantTags.some((id) => !(task.tagIds ?? []).includes(id))) changes.tagIds = wantTags;
        if (projId && task.projectId === "INBOX_PROJECT") changes.projectId = projId;
        if (Object.keys(changes).length) {
          plan(`update SP task "${task.title}": ${Object.keys(changes).join(", ")} <- ${rec.file}`);
          if (!DRY) await sp.req("PATCH", `/tasks/${task.id}`, {...changes, isIgnoreShortSyntax: true});
          stats.updated++;
        }
        st.seenOpen = true;
        st.title = rec.title;
      }
      st.recState = rec.state;
    } catch (e) {
      stats.errors++;
      log(`error on ${rec.file}: ${e.message}`);
    }
  }

  // Record files deleted: their open SP tasks are closed with a note (after two consecutive misses,
  // closedBy "sp-sync"). A file that exists but whose line 3 does not parse is left alone.
  for (const [key, task] of tasksByKey) {
    if (seenKeys.has(key) || task.isDone) continue;
    const root = rootOf(key);
    if (!root || !okRoots.has(root.path)) continue;
    try {
      const st = (state.units[key] ||= {});
      if (!fileMissing(key)) {
        st.missing = 0;
        log(`warning: "${task.title}" (${key}) has an SP task and the file exists, but it is not a scanned record; left alone`);
        continue;
      }
      st.missing = (st.missing || 0) + 1;
      if (first || st.missing < 2) {
        vlog(`record gone for "${task.title}" (${key}), miss ${st.missing}`);
        continue;
      }
      plan(`mark SP task done "${task.title}": record deleted (${key})`);
      const notes = `${task.notes ?? ""}\n\nsp-sync: record deleted ${today()}`;
      await markSpDone(task, st, {notes, isIgnoreShortSyntax: true});
    } catch (e) {
      stats.errors++;
      log(`error on deleted record ${key}: ${e.message}`);
    }
  }

  if (!DRY) saveState(state);
  log(`${DRY ? "dry run: " : ""}${stats.records} records, created ${stats.created}, updated ${stats.updated}, records closed ${stats.closed}, SP tasks done ${stats.spDone}, reopened ${stats.reopened}, errors ${stats.errors}`);
  return 0;
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href;
if (isMain) {
  installSignalHandlers();
  main().then(
    (code) => {
      process.exitCode = code;
    },
    async (e) => {
      if (e?.status === 503) {
        log("SP is still loading; nothing to do");
        process.exitCode = 0;
        return;
      }
      console.log(`sp-sync: fatal: ${redact(e?.message ?? e)}`);
      process.exitCode = 1;
    },
  );
}
