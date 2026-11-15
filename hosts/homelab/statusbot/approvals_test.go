package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	testOwner = int64(4242)
	testID    = "ap-0123456789ab"
	testHash  = "0123456789abcdef"
)

// ── fake Telegram Bot API ─────────────────────────────────────────────────

type tgCall struct {
	Method string
	Form   url.Values
}

type fakeTG struct {
	srv      *httptest.Server
	mu       sync.Mutex
	calls    []tgCall
	nextMsg  int64
	failSend bool
	editErr  string // description of a 400 for every editMessageText
	updates  []string
}

func newFakeTG(t *testing.T) *fakeTG {
	f := &fakeTG{nextMsg: 100}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		method := r.URL.Path[strings.LastIndex(r.URL.Path, "/")+1:]
		f.mu.Lock()
		defer f.mu.Unlock()
		f.calls = append(f.calls, tgCall{method, r.PostForm})
		w.Header().Set("Content-Type", "application/json")
		switch {
		case method == "sendMessage" && f.failSend:
			fmt.Fprint(w, `{"ok":false,"error_code":502,"description":"Bad Gateway"}`)
		case method == "sendMessage":
			f.nextMsg++
			fmt.Fprintf(w, `{"ok":true,"result":{"message_id":%d}}`, f.nextMsg)
		case method == "editMessageText" && f.editErr != "":
			fmt.Fprintf(w, `{"ok":false,"error_code":400,"description":%q}`, f.editErr)
		case method == "getUpdates":
			fmt.Fprintf(w, `{"ok":true,"result":[%s]}`, strings.Join(f.updates, ","))
		default:
			fmt.Fprint(w, `{"ok":true,"result":true}`)
		}
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeTG) of(method string) []tgCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []tgCall
	for _, c := range f.calls {
		if c.Method == method {
			out = append(out, c)
		}
	}
	return out
}

func (f *fakeTG) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.calls)
}

// ── fake gateway bot API (mirrors notices.py: owed, mark_sent) ────────────

type gwNotice struct {
	id, hash16, state, notified string
	messageID                   *int64
	summary                     map[string]any
	firstSeen                   float64
}

type fakeGW struct {
	srv       *httptest.Server
	mu        sync.Mutex
	notices   []*gwNotice
	down      bool
	failSent  bool
	sent      []map[string]any
	decisions []map[string]string
	decStatus int
	decBody   string
	queue     int // 0: 404, else the status
	queueBody string
}

func newFakeGW(t *testing.T) *fakeGW {
	g := &fakeGW{decStatus: 200}
	g.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		g.mu.Lock()
		defer g.mu.Unlock()
		if g.down {
			if c, _, err := w.(http.Hijacker).Hijack(); err == nil {
				c.Close()
			}
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.Method == "GET" && r.URL.Path == "/bot/notices":
			var out []map[string]any
			for _, n := range g.notices {
				if (n.messageID == nil && n.state == "pending") || (n.messageID != nil && n.notified != n.state) {
					v := map[string]any{"id": n.id, "hash16": n.hash16, "state": n.state, "message_id": n.messageID,
						"notified_state": nil, "first_seen_at": n.firstSeen, "url": "https://homelab.example:8443/a/" + n.id}
					if n.notified != "" {
						v["notified_state"] = n.notified
					}
					for k, x := range n.summary {
						v[k] = x
					}
					out = append(out, v)
				}
			}
			json.NewEncoder(w).Encode(map[string]any{"notices": out})
		case r.Method == "POST" && strings.HasPrefix(r.URL.Path, "/bot/notices/") && strings.HasSuffix(r.URL.Path, "/sent"):
			var body map[string]any
			json.NewDecoder(r.Body).Decode(&body)
			if g.failSent {
				w.WriteHeader(503)
				return
			}
			g.sent = append(g.sent, body)
			id := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/bot/notices/"), "/sent")
			for _, n := range g.notices {
				if n.id == id {
					mid := int64(body["message_id"].(float64))
					n.messageID, n.notified = &mid, body["state"].(string)
				}
			}
			fmt.Fprint(w, `{"ok":true}`)
		case r.Method == "POST" && r.URL.Path == "/bot/decision":
			if r.Header.Get("Origin") != "" || r.Header.Get("Content-Type") != "application/json" {
				w.WriteHeader(403)
				return
			}
			var body map[string]string
			json.NewDecoder(r.Body).Decode(&body)
			g.decisions = append(g.decisions, body)
			w.WriteHeader(g.decStatus)
			if g.decBody != "" {
				fmt.Fprint(w, g.decBody)
			} else {
				state := map[string]string{"deny": "denied", "revoke": "revoked"}[body["action"]]
				fmt.Fprintf(w, `{"ok":true,"state":%q}`, state)
			}
		case r.URL.Path == "/healthz/queue":
			if g.queue == 0 {
				w.WriteHeader(404)
				return
			}
			w.WriteHeader(g.queue)
			fmt.Fprint(w, g.queueBody)
		default:
			w.WriteHeader(404)
		}
	}))
	t.Cleanup(g.srv.Close)
	return g
}

func (g *fakeGW) add(id, hash string, firstSeen float64, extra map[string]any) *gwNotice {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := map[string]any{"title": "Push dispatcher p6", "item_id": "item-7", "class": "C4", "kind": "push",
		"expires_at": "2026-11-14T14:00:00Z", "short_hash": groups4(hash),
		"push": map[string]any{"repo": "dispatcher", "remote": "origin", "branch": "p6-core", "count": 3}}
	for k, v := range extra {
		s[k] = v
	}
	n := &gwNotice{id: id, hash16: hash, state: "pending", summary: s, firstSeen: firstSeen}
	g.notices = append(g.notices, n)
	return n
}

func (g *fakeGW) setState(n *gwNotice, state string) {
	g.mu.Lock()
	n.state = state
	g.mu.Unlock()
}

func (g *fakeGW) setDown(v bool) {
	g.mu.Lock()
	g.down = v
	g.mu.Unlock()
}

func (g *fakeGW) decisionCount() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return len(g.decisions)
}

// ── environment ───────────────────────────────────────────────────────────

type env struct {
	tg    *fakeTG
	gw    *fakeGW
	bot   *Bot
	ap    *approver
	clock time.Time
	state string
}

var noon = time.Date(2026, 11, 14, 12, 0, 0, 0, time.UTC)

var ts = float64(noon.Unix())

func newEnv(t *testing.T, mod ...func(*ApprovalsConfig)) *env {
	e := &env{tg: newFakeTG(t), gw: newFakeGW(t), clock: noon, state: filepath.Join(t.TempDir(), "approvals.json")}
	cfg := ApprovalsConfig{BotURL: e.gw.srv.URL, StateFile: e.state}
	for _, m := range mod {
		m(&cfg)
	}
	e.bot = &Bot{cfg: Config{Approvals: cfg}, token: "T0K", chatID: testOwner, http: &http.Client{Timeout: 5 * time.Second}, apiBase: e.tg.srv.URL}
	e.ap = e.newApprover(t)
	return e
}

func (e *env) newApprover(t *testing.T) *approver {
	a, err := newApprover(e.bot)
	if err != nil {
		t.Fatal(err)
	}
	a.now = func() time.Time { return e.clock }
	return a
}

func cbq(from, chat, mid int64, data string) callbackQuery {
	var c callbackQuery
	raw := fmt.Sprintf(`{"id":"cb1","from":{"id":%d},"message":{"message_id":%d,"chat":{"id":%d}},"data":%q}`, from, mid, chat, data)
	if err := json.Unmarshal([]byte(raw), &c); err != nil {
		panic(err)
	}
	return c
}

// announce runs one tick that announces the single pending notice and returns its message id.
func (e *env) announce(t *testing.T) int64 {
	t.Helper()
	e.ap.tick()
	sends := e.tg.of("sendMessage")
	if len(sends) != 1 {
		t.Fatalf("want one sendMessage, got %d", len(sends))
	}
	e.gw.mu.Lock()
	defer e.gw.mu.Unlock()
	if len(e.gw.sent) != 1 {
		t.Fatalf("want one /sent report, got %v", e.gw.sent)
	}
	return int64(e.gw.sent[0]["message_id"].(float64))
}

func markupOf(t *testing.T, form url.Values) [][]button {
	t.Helper()
	var m struct {
		Rows [][]button `json:"inline_keyboard"`
	}
	if err := json.Unmarshal([]byte(form.Get("reply_markup")), &m); err != nil {
		t.Fatalf("reply_markup %q: %v", form.Get("reply_markup"), err)
	}
	return m.Rows
}

// ── notices ───────────────────────────────────────────────────────────────

func TestNoticeIsSentOnceWithButtonsAndReported(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, map[string]any{"title": "Deploy <b>now</b> & more"})
	mid := e.announce(t)

	send := e.tg.of("sendMessage")[0].Form
	if send.Get("chat_id") != strconv.FormatInt(testOwner, 10) || send.Get("parse_mode") != "HTML" {
		t.Fatalf("bad send: %v", send)
	}
	text := send.Get("text")
	for _, want := range []string{"Deploy &lt;b&gt;now&lt;/b&gt; &amp; more", "item item-7", "class C4", "kind push", "dispatcher", "p6-core",
		"3 commit(s)", "expires 2026-11-14T14:00:00Z", "<code>0123 4567 89ab cdef</code>"} {
		if !strings.Contains(text, want) {
			t.Errorf("text lacks %q:\n%s", want, text)
		}
	}
	rows := markupOf(t, send)
	if len(rows) != 1 || len(rows[0]) != 2 {
		t.Fatalf("want one row of two buttons: %v", rows)
	}
	if rows[0][0].URL != "https://homelab.example:8443/a/"+testID {
		t.Errorf("url button: %+v", rows[0][0])
	}
	if d := rows[0][1].CallbackData; d != "d:"+testID+":"+testHash || len(d) > 64 {
		t.Errorf("deny data %q", d)
	}
	e.gw.mu.Lock()
	rep := e.gw.sent[0]
	e.gw.mu.Unlock()
	if rep["state"] != "pending" || int64(rep["message_id"].(float64)) != mid {
		t.Errorf("report: %v", rep)
	}
	// Reported, so the gateway no longer lists it: the next ticks send nothing.
	e.ap.tick()
	e.ap.tick()
	if n := len(e.tg.of("sendMessage")); n != 1 {
		t.Fatalf("announced again: %d sends", n)
	}
}

func TestGrantedEditsToRevokeThenOutcomesRemoveKeyboard(t *testing.T) {
	for _, outcome := range []string{"used", "denied", "revoked", "expired", "cancelled"} {
		t.Run(outcome, func(t *testing.T) {
			e := newEnv(t)
			n := e.gw.add(testID, testHash, ts, nil)
			mid := e.announce(t)

			e.gw.setState(n, "granted")
			e.ap.tick()
			edits := e.tg.of("editMessageText")
			if len(edits) != 1 {
				t.Fatalf("want one edit, got %d", len(edits))
			}
			f := edits[0].Form
			if f.Get("message_id") != strconv.FormatInt(mid, 10) || !strings.Contains(f.Get("text"), "Granted") {
				t.Errorf("granted edit: %v", f)
			}
			rows := markupOf(t, f)
			if len(rows) != 1 || len(rows[0]) != 1 || rows[0][0].CallbackData != "r:"+testID+":"+testHash {
				t.Errorf("revoke keyboard: %v", rows)
			}
			if _, ok := e.ap.get(testID); !ok {
				t.Fatal("a granted approval must stay remembered for Revoke")
			}

			e.gw.setState(n, outcome)
			e.ap.tick()
			edits = e.tg.of("editMessageText")
			if len(edits) != 2 {
				t.Fatalf("want two edits, got %d", len(edits))
			}
			f = edits[1].Form
			if !strings.Contains(strings.ToLower(f.Get("text")), outcome) {
				t.Errorf("outcome text lacks %q: %s", outcome, f.Get("text"))
			}
			if rows := markupOf(t, f); len(rows) != 0 {
				t.Errorf("outcome keeps a keyboard: %v", rows)
			}
			if _, ok := e.ap.get(testID); ok {
				t.Error("a finished approval must be forgotten")
			}
			e.ap.tick()
			if len(e.tg.of("editMessageText")) != 2 {
				t.Error("edited again after being reported")
			}
		})
	}
}

func TestPendingGoesStraightToOutcomeWhenGrantAndUseAreWithinOnePoll(t *testing.T) {
	e := newEnv(t)
	n := e.gw.add(testID, testHash, ts, nil)
	e.announce(t)
	e.gw.setState(n, "used")
	e.ap.tick()
	edits := e.tg.of("editMessageText")
	if len(edits) != 1 || len(markupOf(t, edits[0].Form)) != 0 {
		t.Fatalf("edits: %v", edits)
	}
}

func TestEditTelegramRefusesForeverIsNotRetried(t *testing.T) {
	e := newEnv(t)
	n := e.gw.add(testID, testHash, ts, nil)
	e.announce(t)
	e.tg.editErr = "Bad Request: message to edit not found"
	e.gw.setState(n, "denied")
	e.ap.tick()
	e.ap.tick()
	if got := len(e.tg.of("editMessageText")); got != 1 {
		t.Fatalf("a deleted message must not be edited every poll: %d edits", got)
	}
}

func TestTelegramSendFailureIsRetriedAndNeverReported(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	e.tg.failSend = true
	e.ap.tick()
	e.gw.mu.Lock()
	reported := len(e.gw.sent)
	e.gw.mu.Unlock()
	if reported != 0 {
		t.Fatal("reported a message that was never sent")
	}
	e.tg.failSend = false
	e.ap.tick()
	if len(e.gw.sent) != 1 {
		t.Fatalf("not announced after Telegram recovered: %v", e.gw.sent)
	}
}

func TestLostSentReportDoesNotDuplicateTheMessage(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	e.gw.failSent = true
	e.ap.tick()
	e.ap.tick()
	if n := len(e.tg.of("sendMessage")); n != 1 {
		t.Fatalf("%d messages for one approval", n)
	}
	e.gw.mu.Lock()
	e.gw.failSent = false
	e.gw.mu.Unlock()
	e.ap.tick()
	if len(e.gw.sent) != 1 || len(e.tg.of("sendMessage")) != 1 {
		t.Fatalf("recovery: reports %v, sends %d", e.gw.sent, len(e.tg.of("sendMessage")))
	}
}

func TestOneBadNoticeDoesNotHideTheOthers(t *testing.T) {
	e := newEnv(t)
	e.gw.add("bad id!", testHash, ts, nil)
	e.gw.add("ap-"+strings.Repeat("a", 60), testHash, ts, nil) // too long for a 64-byte callback
	e.gw.add(testID, "nothex", ts, nil)
	e.gw.add("ap-ffffffffffff", "fedcba9876543210", ts+1, nil)
	e.ap.tick()
	sends := e.tg.of("sendMessage")
	if len(sends) != 1 || !strings.Contains(markupOf(t, sends[0].Form)[0][1].CallbackData, "ap-ffffffffffff") {
		t.Fatalf("sends: %v", sends)
	}
}

// ── callbacks ─────────────────────────────────────────────────────────────

func TestDenyFromOwnerPostsDecisionAndRemovesKeyboard(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)

	e.ap.callback(cbq(testOwner, testOwner, mid, "d:"+testID+":"+testHash))
	e.gw.mu.Lock()
	dec := e.gw.decisions
	e.gw.mu.Unlock()
	if len(dec) != 1 || dec[0]["id"] != testID || dec[0]["action"] != "deny" || dec[0]["hash16"] != testHash {
		t.Fatalf("decision: %v", dec)
	}
	ans := e.tg.of("answerCallbackQuery")
	if len(ans) != 1 || ans[0].Form.Get("callback_query_id") != "cb1" || ans[0].Form.Get("text") != "Denied" {
		t.Fatalf("answer: %v", ans)
	}
	rm := e.tg.of("editMessageReplyMarkup")
	if len(rm) != 1 || rm[0].Form.Get("message_id") != strconv.FormatInt(mid, 10) || len(markupOf(t, rm[0].Form)) != 0 {
		t.Fatalf("keyboard not removed: %v", rm)
	}
}

func TestRevokeFromOwnerAfterGrant(t *testing.T) {
	e := newEnv(t)
	n := e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)
	e.gw.setState(n, "granted")
	e.ap.tick()

	e.ap.callback(cbq(testOwner, testOwner, mid, "r:"+testID+":"+testHash))
	if len(e.gw.decisions) != 1 || e.gw.decisions[0]["action"] != "revoke" {
		t.Fatalf("decision: %v", e.gw.decisions)
	}
	if got := e.tg.of("answerCallbackQuery")[0].Form.Get("text"); got != "Revoked" {
		t.Fatalf("answer %q", got)
	}
}

func TestForgedCallbacksAreIgnoredButAnswered(t *testing.T) {
	e := newEnv(t)
	n := e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)
	good := "d:" + testID + ":" + testHash
	cases := map[string]callbackQuery{
		"other from.id":        cbq(999, testOwner, mid, good),
		"other chat":           cbq(testOwner, 999, mid, good),
		"other message_id":     cbq(testOwner, testOwner, mid+1, good),
		"wrong hash16":         cbq(testOwner, testOwner, mid, "d:"+testID+":ffffffffffffffff"),
		"unknown id":           cbq(testOwner, testOwner, mid, "d:ap-000000000000:"+testHash),
		"revoke while pending": cbq(testOwner, testOwner, mid, "r:"+testID+":"+testHash),
		"bad action":           cbq(testOwner, testOwner, mid, "g:"+testID+":"+testHash),
		"no hash":              cbq(testOwner, testOwner, mid, "d:"+testID),
		"extra field":          cbq(testOwner, testOwner, mid, good+":x"),
		"empty":                cbq(testOwner, testOwner, mid, ""),
		"upper-case hash":      cbq(testOwner, testOwner, mid, "d:"+testID+":0123456789ABCDEF"),
		"id with path":         cbq(testOwner, testOwner, mid, "d:../x:"+testHash),
		"both wrong":           cbq(1, 2, 3, good),
		"zero message":         cbq(testOwner, testOwner, 0, good),
	}
	for name, c := range cases {
		before := len(e.tg.of("answerCallbackQuery"))
		e.ap.callback(c)
		if got := len(e.tg.of("answerCallbackQuery")); got != before+1 {
			t.Errorf("%s: the callback must be answered exactly once", name)
		}
		if e.gw.decisionCount() != 0 {
			t.Fatalf("%s: a forged callback reached the gateway", name)
		}
	}
	// A callback with no message at all (an inline-mode press) is answered and ignored too.
	var nomsg callbackQuery
	_ = json.Unmarshal([]byte(`{"id":"cb2","from":{"id":4242},"data":"`+good+`"}`), &nomsg)
	e.ap.callback(nomsg)
	if e.gw.decisionCount() != 0 || len(e.tg.of("answerCallbackQuery")) != len(cases)+1 {
		t.Fatal("callback without a message")
	}
	// A deny for a granted approval is stale too.
	e.gw.setState(n, "granted")
	e.ap.tick()
	e.ap.callback(cbq(testOwner, testOwner, mid, good))
	if e.gw.decisionCount() != 0 {
		t.Fatal("deny pressed on a granted approval reached the gateway")
	}
	// The genuine one still works afterwards (nothing above poisoned the state).
	e.ap.callback(cbq(testOwner, testOwner, mid, "r:"+testID+":"+testHash))
	if e.gw.decisionCount() != 1 {
		t.Fatal("the owner's genuine revoke was lost")
	}
}

func TestGatewayRefusingTheHashIsIgnored(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)
	e.gw.decStatus = 409
	e.gw.decBody = `{"ok":false,"ignored":true,"error":"hash_mismatch","message":"x"}`
	e.ap.callback(cbq(testOwner, testOwner, mid, "d:"+testID+":"+testHash))
	if got := e.tg.of("answerCallbackQuery")[0].Form.Get("text"); got != "Ignored" {
		t.Fatalf("answer %q", got)
	}
	if len(e.tg.of("editMessageReplyMarkup")) != 0 {
		t.Fatal("keyboard removed after a refused decision")
	}
}

func TestGatewayDownOnDecisionKeepsTheButtonAndAnswers(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)
	e.gw.setDown(true)
	e.ap.callback(cbq(testOwner, testOwner, mid, "d:"+testID+":"+testHash))
	ans := e.tg.of("answerCallbackQuery")
	if len(ans) != 1 || !strings.Contains(ans[0].Form.Get("text"), "try again") {
		t.Fatalf("answer: %v", ans)
	}
	if len(e.tg.of("editMessageReplyMarkup")) != 0 {
		t.Fatal("keyboard removed though nothing was denied")
	}
	e.gw.setDown(false)
	e.ap.callback(cbq(testOwner, testOwner, mid, "d:"+testID+":"+testHash))
	if e.gw.decisionCount() != 1 {
		t.Fatal("the retry did not go through")
	}
}

func TestCallbackRoutedThroughDispatchAndAnsweredWhenApprovalsAreOff(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)
	var u update
	raw := fmt.Sprintf(`{"update_id":9,"callback_query":{"id":"cb7","from":{"id":%d},"message":{"message_id":%d,"chat":{"id":%d}},"data":"d:%s:%s"}}`,
		testOwner, mid, testOwner, testID, testHash)
	if err := json.Unmarshal([]byte(raw), &u); err != nil {
		t.Fatal(err)
	}
	e.bot.dispatch(e.ap, u)
	if e.gw.decisionCount() != 1 || len(e.tg.of("answerCallbackQuery")) != 1 {
		t.Fatal("dispatch did not route the callback")
	}
	e.bot.dispatch(nil, u) // approvals off: answered, nothing posted
	if e.gw.decisionCount() != 1 || len(e.tg.of("answerCallbackQuery")) != 2 {
		t.Fatal("with approvals off a callback must be answered and dropped")
	}
}

func TestGetUpdatesAsksForCallbackQueries(t *testing.T) {
	e := newEnv(t)
	e.tg.updates = []string{`{"update_id":5}`}
	ups, err := e.bot.getUpdates(5, 0)
	if err != nil || len(ups) != 1 || ups[0].UpdateID != 5 {
		t.Fatalf("%v %v", ups, err)
	}
	got := e.tg.of("getUpdates")[0].Form.Get("allowed_updates")
	var allowed []string
	if err := json.Unmarshal([]byte(got), &allowed); err != nil || len(allowed) != 2 || allowed[0] != "message" || allowed[1] != "callback_query" {
		t.Fatalf("allowed_updates %q", got)
	}
}

func TestOldMessageRoutingUnchanged(t *testing.T) {
	e := newEnv(t)
	var u update
	_ = json.Unmarshal([]byte(`{"update_id":1,"message":{"chat":{"id":999},"text":"/restart x"}}`), &u)
	e.bot.dispatch(e.ap, u) // another chat: ignored
	if e.tg.count() != 0 {
		t.Fatal("a message from another chat was answered")
	}
}

// ── state file ────────────────────────────────────────────────────────────

func TestStateSurvivesARestart(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)

	e.ap = e.newApprover(t) // statusbot restarted
	e.ap.callback(cbq(testOwner, testOwner, mid, "d:"+testID+":"+testHash))
	if e.gw.decisionCount() != 1 {
		t.Fatal("the stored message id was lost over a restart")
	}
	if fi, err := os.Stat(e.state); err != nil || fi.Mode().Perm() != 0o600 {
		t.Fatalf("state file: %v %v", fi, err)
	}
}

func TestMissingOrBrokenStateFileFailsSafe(t *testing.T) {
	e := newEnv(t)
	if err := os.WriteFile(e.state, []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	a := e.newApprover(t)
	a.callback(cbq(testOwner, testOwner, 101, "d:"+testID+":"+testHash))
	if e.gw.decisionCount() != 0 {
		t.Fatal("a callback was honoured with no remembered message")
	}
	if len(e.tg.of("answerCallbackQuery")) != 1 {
		t.Fatal("not answered")
	}
}

func TestStateFileLostAdoptsTheGatewaysMessageForLaterEdits(t *testing.T) {
	e := newEnv(t)
	n := e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t)
	if err := os.Remove(e.state); err != nil {
		t.Fatal(err)
	}
	e.ap = e.newApprover(t)
	e.gw.setState(n, "granted")
	e.ap.tick()
	edits := e.tg.of("editMessageText")
	if len(edits) != 1 || edits[0].Form.Get("message_id") != strconv.FormatInt(mid, 10) {
		t.Fatalf("edit after losing the state file: %v", edits)
	}
	// And Revoke now works, on the adopted message.
	e.ap.callback(cbq(testOwner, testOwner, mid, "r:"+testID+":"+testHash))
	if e.gw.decisionCount() != 1 {
		t.Fatal("revoke after adoption")
	}
}

func TestOldPendingEntriesArePruned(t *testing.T) {
	e := newEnv(t)
	e.ap.put(testID, tracked{MessageID: 5, Hash16: testHash, State: "pending", FirstSeen: float64(noon.Add(-8 * 24 * time.Hour).Unix())})
	e.ap.put("ap-aaaaaaaaaaaa", tracked{MessageID: 6, Hash16: testHash, State: "pending", FirstSeen: float64(noon.Add(-time.Hour).Unix())})
	e.ap.tick()
	if _, ok := e.ap.get(testID); ok {
		t.Error("an 8-day-old entry should be pruned")
	}
	if _, ok := e.ap.get("ap-aaaaaaaaaaaa"); !ok {
		t.Error("a fresh entry was pruned")
	}
}

// ── quiet hours ───────────────────────────────────────────────────────────

func TestQuietHoursWindow(t *testing.T) {
	q := quietHours{23 * 60, 9 * 60}
	at := func(h, m int) time.Time { return time.Date(2026, 11, 14, h, m, 0, 0, time.UTC) }
	for _, c := range []struct {
		h, m int
		want bool
	}{{22, 59, false}, {23, 0, true}, {23, 59, true}, {0, 0, true}, {3, 30, true}, {8, 59, true}, {9, 0, false}, {12, 0, false}} {
		if got := q.active(at(c.h, c.m)); got != c.want {
			t.Errorf("%02d:%02d: got %v", c.h, c.m, got)
		}
	}
	if (quietHours{600, 600}).active(at(10, 0)) {
		t.Error("equal bounds must mean no quiet hours")
	}
	day := quietHours{13 * 60, 15 * 60}
	if !day.active(at(14, 0)) || day.active(at(15, 0)) || day.active(at(12, 59)) {
		t.Error("a window inside one day")
	}
}

func TestQuietHoursHoldNewNoticesUntilNine(t *testing.T) {
	e := newEnv(t)
	e.clock = time.Date(2026, 11, 14, 23, 30, 0, 0, time.UTC)
	e.gw.add(testID, testHash, ts, nil)
	e.ap.tick()
	e.clock = time.Date(2026, 11, 15, 8, 59, 0, 0, time.UTC)
	e.ap.tick()
	if e.tg.count() != 0 {
		t.Fatalf("a notice was sent in quiet hours: %v", e.tg.calls)
	}
	e.clock = time.Date(2026, 11, 15, 9, 0, 0, 0, time.UTC)
	e.ap.tick()
	if len(e.tg.of("sendMessage")) != 1 {
		t.Fatal("the held notice was not released at 09:00")
	}
}

func TestQuietHoursDoNotHoldEditsOrDecisions(t *testing.T) {
	e := newEnv(t)
	n := e.gw.add(testID, testHash, ts, nil)
	mid := e.announce(t) // noon
	e.clock = time.Date(2026, 11, 14, 23, 30, 0, 0, time.UTC)
	e.gw.setState(n, "granted")
	e.ap.tick()
	if len(e.tg.of("editMessageText")) != 1 {
		t.Fatal("an edit of an already announced notice was held")
	}
	e.ap.callback(cbq(testOwner, testOwner, mid, "r:"+testID+":"+testHash))
	if e.gw.decisionCount() != 1 {
		t.Fatal("a revoke was held in quiet hours")
	}
}

func TestHeldNoticeThatIsDecidedMeanwhileIsNeverSent(t *testing.T) {
	e := newEnv(t)
	e.clock = time.Date(2026, 11, 14, 23, 30, 0, 0, time.UTC)
	n := e.gw.add(testID, testHash, ts, nil)
	e.ap.tick()
	e.gw.setState(n, "expired")
	e.clock = time.Date(2026, 11, 15, 9, 1, 0, 0, time.UTC)
	e.ap.tick()
	if e.tg.count() != 0 {
		t.Fatal("an expired held notice was announced")
	}
}

func TestQuietHoursAreConfigurable(t *testing.T) {
	e := newEnv(t, func(c *ApprovalsConfig) { c.QuietStart, c.QuietEnd = "12:00", "13:00" })
	e.gw.add(testID, testHash, ts, nil)
	e.ap.tick() // noon: now quiet
	if e.tg.count() != 0 {
		t.Fatal("custom quiet hours ignored")
	}
	e.clock = noon.Add(time.Hour)
	e.ap.tick()
	if len(e.tg.of("sendMessage")) != 1 {
		t.Fatal("not released at the custom end")
	}
}

func TestBadConfigIsRefused(t *testing.T) {
	for _, c := range []ApprovalsConfig{
		{BotURL: "127.0.0.1:37743"},
		{BotURL: "ftp://x"},
		{BotURL: "http://127.0.0.1:1", QuietStart: "25:00"},
		{BotURL: "http://127.0.0.1:1", QuietEnd: "9"},
	} {
		if _, err := newApprover(&Bot{cfg: Config{Approvals: c}}); err == nil {
			t.Errorf("accepted %+v", c)
		}
	}
}

// ── gateway down ──────────────────────────────────────────────────────────

func TestGatewayDownDoesNotCrashAndRecovers(t *testing.T) {
	e := newEnv(t)
	e.gw.add(testID, testHash, ts, nil)
	e.gw.setDown(true)
	for i := 0; i < 3; i++ {
		e.ap.tick() // must not panic
	}
	if e.tg.count() != 0 {
		t.Fatal("Telegram was used while the gateway was down")
	}
	e.gw.setDown(false)
	e.ap.tick()
	if len(e.tg.of("sendMessage")) != 1 {
		t.Fatal("no announcement after the gateway came back")
	}
}

func TestGatewayAnswersGarbage(t *testing.T) {
	for name, h := range map[string]http.HandlerFunc{
		"500":       func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(500) },
		"html":      func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "<html>") },
		"wrong":     func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"notices":"x"}`) },
		"null item": func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"notices":[null,1,"a",{"id":5}]}`) },
	} {
		t.Run(name, func(t *testing.T) {
			srv := httptest.NewServer(h)
			defer srv.Close()
			e := newEnv(t, func(c *ApprovalsConfig) { c.BotURL = srv.URL })
			e.ap.tick()
			if e.tg.count() != 0 {
				t.Fatal("acted on garbage")
			}
		})
	}
}

// ── digest line ───────────────────────────────────────────────────────────

func TestDigestLinePendingAndQueue(t *testing.T) {
	e := newEnv(t)
	e.gw.queue = 200
	e.gw.queueBody = `{"queued":5,"delivering":0,"delivered":9,"failed":0,"oldest_queued_age_seconds":72000}`
	// Two approvals: one announced earlier (only in the state file), one held in quiet hours (owed, unannounced).
	e.ap.put("ap-aaaaaaaaaaaa", tracked{MessageID: 7, Hash16: testHash, State: "pending", FirstSeen: float64(noon.Add(-3 * time.Hour).Unix())})
	e.gw.add(testID, testHash, float64(noon.Add(-30*time.Minute).Unix()), nil)

	line := e.ap.digestLine()
	for _, want := range []string{"2 pending (oldest 3h)", "5 queued (oldest 20h)"} {
		if !strings.Contains(line, want) {
			t.Errorf("line lacks %q: %s", want, line)
		}
	}
}

func TestDigestLineIgnoresApprovalsAlreadyDecided(t *testing.T) {
	e := newEnv(t)
	e.ap.put(testID, tracked{MessageID: 7, Hash16: testHash, State: "pending", FirstSeen: float64(noon.Unix())})
	n := e.gw.add(testID, testHash, float64(noon.Unix()), nil)
	e.gw.setState(n, "used")
	mid := int64(7)
	n.messageID, n.notified = &mid, "pending" // owed: an edit to "used"
	if line := e.ap.digestLine(); !strings.Contains(line, "none pending") {
		t.Fatalf("a used approval counted as pending: %s", line)
	}
}

func TestDigestLineWhenQueueEndpointIsMissingOrDown(t *testing.T) {
	e := newEnv(t) // /healthz/queue: 404 (ticket 51 not deployed)
	if line := e.ap.digestLine(); !strings.Contains(line, "none pending") || !strings.Contains(line, "Captures: n/a") || strings.Contains(line, "gateway unreachable") {
		t.Fatalf("404: %s", line)
	}
	e.gw.setDown(true)
	line := e.ap.digestLine()
	if !strings.Contains(line, "Approvals: n/a (gateway unreachable)") || !strings.Contains(line, "Captures: n/a (gateway unreachable)") {
		t.Fatalf("down: %s", line)
	}
	e.ap.put(testID, tracked{MessageID: 7, Hash16: testHash, State: "pending", FirstSeen: float64(noon.Add(-2 * time.Hour).Unix())})
	if line := e.ap.digestLine(); !strings.Contains(line, "1 pending (oldest 2h) (gateway unreachable, last known)") {
		t.Fatalf("down with state: %s", line)
	}
}

func TestDigestLineQueueAlertsWithAndWithoutBody(t *testing.T) {
	e := newEnv(t)
	e.gw.queue, e.gw.queueBody = 503, ""
	if line := e.ap.digestLine(); !strings.Contains(line, "⚠️ queue alert") {
		t.Fatalf("503 without body: %s", line)
	}
	e.gw.queue, e.gw.queueBody = 200, "ok"
	if line := e.ap.digestLine(); !strings.Contains(line, "queue ok") {
		t.Fatalf("200 without JSON: %s", line)
	}
	e.gw.queue, e.gw.queueBody = 503, `{"queued":2,"failed":1,"oldest_queued_age_seconds":90000}`
	line := e.ap.digestLine()
	if !strings.Contains(line, "2 queued (oldest 25h)") || !strings.Contains(line, "1 failed") {
		t.Fatalf("503 with body: %s", line)
	}
	e.gw.queue, e.gw.queueBody = 200, `{"queued":0,"failed":0,"oldest_queued_age_seconds":null}`
	if line := e.ap.digestLine(); !strings.Contains(line, "Captures: none queued") {
		t.Fatalf("empty queue: %s", line)
	}
}

func TestApprovalsLineIsEmptyWhenOff(t *testing.T) {
	if got := (&Bot{}).approvalsLine(); got != "" {
		t.Fatalf("line with approvals off: %q", got)
	}
	// A broken botUrl must not break the digest either.
	if got := (&Bot{cfg: Config{Approvals: ApprovalsConfig{BotURL: "nope"}}}).approvalsLine(); got != "" {
		t.Fatalf("line with a bad url: %q", got)
	}
}

func TestApprovalsLineReadsTheConfiguredGateway(t *testing.T) {
	e := newEnv(t)
	e.gw.queue, e.gw.queueBody = 200, `{"queued":1,"failed":0,"oldest_queued_age_seconds":600}`
	line := e.bot.approvalsLine()
	if !strings.HasPrefix(line, "🔐 Approvals: none pending · Captures: 1 queued (oldest 10m)") {
		t.Fatalf("line: %s", line)
	}
}

func TestTokenNeverReachesTheGateway(t *testing.T) {
	e := newEnv(t)
	var seen []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b := new(strings.Builder)
		_ = r.Header.Write(b)
		seen = append(seen, r.URL.String()+b.String())
		fmt.Fprint(w, `{"notices":[]}`)
	}))
	defer srv.Close()
	e.bot.cfg.Approvals.BotURL = srv.URL
	a := e.newApprover(t)
	a.tick()
	_ = a.digestLine()
	for _, s := range seen {
		if strings.Contains(s, "T0K") {
			t.Fatalf("the Telegram token was sent to the gateway: %s", s)
		}
	}
}
