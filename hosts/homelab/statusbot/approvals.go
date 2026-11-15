package main

// Approval notices (dispatcher stage 1d, spec P3). The dispatcher gateway on this
// host keeps what the owner has to decide; statusbot only announces it and lets
// the owner take permission away:
//
//	GET  {botUrl}/bot/notices           what is owed: approvals to announce, states to edit in
//	POST {botUrl}/bot/notices/<id>/sent the Telegram message id and the state drawn into it
//	POST {botUrl}/bot/decision          {"id","action":"deny"|"revoke","hash16"}
//	GET  {botUrl}/healthz/queue         digest only: queued captures (200 or 503, optional JSON)
//
// There is no grant path here: statusbot never grants. A forged or stale button
// can at worst deny or revoke, and the core checks the hash prefix again.
//
// statusbot keeps one small state file (approvals.json). The gateway lists only
// what is owed, so an announced approval vanishes from /bot/notices until its
// state changes; the file is what lets a callback be checked against the stored
// message id and lets the digest count the approvals still waiting.

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ApprovalsConfig is the "approvals" object of statusbot.json. Everything but
// botUrl has a default; with no botUrl the feature is off and statusbot behaves
// as before.
type ApprovalsConfig struct {
	// BotURL is the gateway's bot listener, e.g. "http://127.0.0.1:37743".
	BotURL string `json:"botUrl"`
	// OwnerID is the Telegram user id a callback must come from; 0 means the
	// chat id (TELEGRAM_CHAT_ID), which is the same number in a private chat.
	OwnerID int64 `json:"ownerId,omitempty"`
	// PollSeconds is how often /bot/notices is read; 0 means 15.
	PollSeconds int `json:"pollSeconds,omitempty"`
	// QuietStart and QuietEnd ("HH:MM", host local time) hold new notices; empty
	// means 23:00 and 09:00, equal values mean no quiet hours.
	QuietStart string `json:"quietStart,omitempty"`
	QuietEnd   string `json:"quietEnd,omitempty"`
	// StateFile is where announced approvals are remembered across restarts;
	// empty means /var/cache/statusbot/approvals.json.
	StateFile string `json:"stateFile,omitempty"`
}

const (
	defaultPollSeconds = 15
	defaultStateFile   = "/var/cache/statusbot/approvals.json"
	// A callback's data is at most 64 bytes: "d:" + id + ":" + 16 hex = id + 19.
	maxIDLen       = 45
	maxStateAge    = 7 * 24 * time.Hour
	gatewayBodyMax = 1 << 20
)

var (
	idRe   = regexp.MustCompile(`^[A-Za-z0-9_-]{1,45}$`)
	hashRe = regexp.MustCompile(`^[0-9a-f]{16}$`)
)

var terminalStates = map[string]bool{"denied": true, "revoked": true, "used": true, "expired": true, "cancelled": true}

var knownStates = map[string]bool{"pending": true, "granted": true, "denied": true, "revoked": true, "used": true, "expired": true, "cancelled": true}

// ── quiet hours ───────────────────────────────────────────────────────────

type quietHours struct{ start, end int } // minutes after local midnight

func parseClock(s, def string) (int, error) {
	if s == "" {
		s = def
	}
	h, m, ok := strings.Cut(s, ":")
	hh, err1 := strconv.Atoi(h)
	mm, err2 := strconv.Atoi(m)
	if !ok || err1 != nil || err2 != nil || hh < 0 || hh > 23 || mm < 0 || mm > 59 {
		return 0, fmt.Errorf("approvals: %q is not HH:MM", s)
	}
	return hh*60 + mm, nil
}

// active reports whether t falls in [start, end), also across midnight.
func (q quietHours) active(t time.Time) bool {
	m := t.Hour()*60 + t.Minute()
	switch {
	case q.start == q.end:
		return false
	case q.start < q.end:
		return m >= q.start && m < q.end
	default:
		return m >= q.start || m < q.end
	}
}

// ── what the gateway sends ────────────────────────────────────────────────

type notice struct {
	ID            string  `json:"id"`
	Hash16        string  `json:"hash16"`
	State         string  `json:"state"`
	MessageID     *int64  `json:"message_id"`
	NotifiedState *string `json:"notified_state"`
	URL           string  `json:"url"`
	FirstSeenAt   float64 `json:"first_seen_at"`
	Title         string  `json:"title"`
	ItemID        string  `json:"item_id"`
	Class         string  `json:"class"`
	Kind          string  `json:"kind"`
	ExpiresAt     string  `json:"expires_at"`
	ShortHash     string  `json:"short_hash"`
	DecidedVia    string  `json:"decided_via"`
	Push          *struct {
		Repo   string `json:"repo"`
		Remote string `json:"remote"`
		Branch string `json:"branch"`
		Count  any    `json:"count"`
	} `json:"push"`
}

func (n notice) valid() bool {
	return idRe.MatchString(n.ID) && hashRe.MatchString(n.Hash16) && knownStates[n.State]
}

// tracked is what statusbot remembers about one announced approval.
type tracked struct {
	MessageID int64   `json:"message_id"`
	Hash16    string  `json:"hash16"`
	State     string  `json:"state"` // the state drawn into the message
	FirstSeen float64 `json:"first_seen"`
}

type stateFile struct {
	Approvals map[string]*tracked `json:"approvals"`
}

// ── the approver ──────────────────────────────────────────────────────────

type approver struct {
	b        *Bot
	base     string
	hc       *http.Client
	now      func() time.Time
	owner    int64
	quiet    quietHours
	interval time.Duration
	path     string

	mu      sync.Mutex
	state   map[string]*tracked
	gwDown  bool
	saveErr bool
}

func newApprover(b *Bot) (*approver, error) {
	c := b.cfg.Approvals
	u, err := url.Parse(c.BotURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, fmt.Errorf("approvals.botUrl %q is not an http(s) URL", c.BotURL)
	}
	qs, err := parseClock(c.QuietStart, "23:00")
	if err != nil {
		return nil, err
	}
	qe, err := parseClock(c.QuietEnd, "09:00")
	if err != nil {
		return nil, err
	}
	a := &approver{
		b:        b,
		base:     strings.TrimRight(c.BotURL, "/"),
		hc:       &http.Client{Timeout: 10 * time.Second},
		now:      time.Now,
		owner:    c.OwnerID,
		quiet:    quietHours{qs, qe},
		interval: defaultPollSeconds * time.Second,
		path:     c.StateFile,
		state:    map[string]*tracked{},
	}
	if a.owner == 0 {
		a.owner = b.chatID
	}
	if c.PollSeconds > 0 {
		a.interval = time.Duration(c.PollSeconds) * time.Second
	}
	if a.path == "" {
		a.path = defaultStateFile
	}
	a.load()
	return a, nil
}

func (a *approver) load() {
	raw, err := os.ReadFile(a.path)
	if errors.Is(err, os.ErrNotExist) {
		return
	}
	var f stateFile
	if err == nil {
		err = json.Unmarshal(raw, &f)
	}
	if err != nil {
		// Fail safe: no remembered message ids means callbacks are ignored.
		log.Printf("approvals: ignoring state file %s: %v", a.path, err)
		return
	}
	for id, t := range f.Approvals {
		if t != nil && idRe.MatchString(id) && hashRe.MatchString(t.Hash16) && knownStates[t.State] && t.MessageID > 0 {
			a.state[id] = t
		}
	}
}

// save writes the state file; the caller holds a.mu.
func (a *approver) save() {
	raw, err := json.Marshal(stateFile{Approvals: a.state})
	if err == nil {
		tmp := a.path + ".tmp"
		if err = os.WriteFile(tmp, raw, 0o600); err == nil {
			err = os.Rename(tmp, a.path)
		}
	}
	switch {
	case err != nil && !a.saveErr:
		log.Printf("approvals: cannot save %s: %v (callbacks will not survive a restart)", a.path, err)
		a.saveErr = true
	case err == nil:
		a.saveErr = false
	}
}

func (a *approver) get(id string) (tracked, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if t := a.state[id]; t != nil {
		return *t, true
	}
	return tracked{}, false
}

func (a *approver) put(id string, t tracked) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.state[id] = &t
	a.save()
}

func (a *approver) drop(id string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, ok := a.state[id]; ok {
		delete(a.state, id)
		a.save()
	}
}

// ── talking to the gateway ────────────────────────────────────────────────

func (a *approver) gateway(method, path string, body any) (int, []byte, error) {
	var rd io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return 0, nil, err
		}
		rd = bytes.NewReader(raw)
	}
	req, err := http.NewRequest(method, a.base+path, rd)
	if err != nil {
		return 0, nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := a.hc.Do(req)
	if err != nil {
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err
		}
		return 0, nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, gatewayBodyMax))
	return resp.StatusCode, raw, err
}

// fetch reads /bot/notices. A notice that does not parse or validate is skipped,
// not fatal: one bad row must not hide the others.
func (a *approver) fetch() ([]notice, error) {
	code, raw, err := a.gateway("GET", "/bot/notices", nil)
	if err != nil {
		return nil, err
	}
	if code != http.StatusOK {
		return nil, fmt.Errorf("/bot/notices: HTTP %d", code)
	}
	var body struct {
		Notices []json.RawMessage `json:"notices"`
	}
	if err := json.Unmarshal(raw, &body); err != nil {
		return nil, fmt.Errorf("/bot/notices: %w", err)
	}
	var out []notice
	for _, r := range body.Notices {
		var n notice
		if json.Unmarshal(r, &n) == nil && n.valid() {
			out = append(out, n)
		}
	}
	return out, nil
}

// ── the notice loop ───────────────────────────────────────────────────────

func (a *approver) loop() {
	for {
		a.tick()
		time.Sleep(a.interval)
	}
}

// tick is one poll: it must never crash the bot, whatever the gateway says.
func (a *approver) tick() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("approvals: %v", r)
		}
	}()
	ns, err := a.fetch()
	if err != nil {
		if !a.gwDown {
			log.Printf("approvals: gateway unreachable, retrying every %s: %v", a.interval, err)
			a.gwDown = true
		}
		return
	}
	if a.gwDown {
		log.Print("approvals: gateway is back")
		a.gwDown = false
	}
	for _, n := range ns {
		a.process(n)
	}
	a.prune()
}

func (a *approver) process(n notice) {
	t, known := a.get(n.ID)
	if n.MessageID == nil { // announce
		if n.State != "pending" {
			return
		}
		if !known {
			if a.quiet.active(a.now()) {
				return // held until the quiet hours end
			}
			mid, err := a.sendNotice(n)
			if err != nil {
				log.Printf("approvals: announce %s: %v", n.ID, err)
				return
			}
			t = tracked{MessageID: mid, Hash16: n.Hash16, State: "pending", FirstSeen: n.FirstSeenAt}
			a.put(n.ID, t)
		}
		// Sent but not yet reported (the report failed last time): report, never resend.
		a.report(n.ID, t)
		return
	}
	// update: the gateway's message id and hash are the record; ours may be missing or older.
	if !known || t.MessageID != *n.MessageID || t.Hash16 != n.Hash16 {
		drawn := "pending"
		if n.NotifiedState != nil && knownStates[*n.NotifiedState] {
			drawn = *n.NotifiedState
		}
		if known && t.MessageID == *n.MessageID {
			drawn = t.State
		}
		t = tracked{MessageID: *n.MessageID, Hash16: n.Hash16, State: drawn, FirstSeen: n.FirstSeenAt}
	}
	if t.State != n.State {
		if err := a.editNotice(n, t.MessageID); err != nil && !editIsFinal(err) {
			log.Printf("approvals: edit %s: %v", n.ID, err)
			a.put(n.ID, t)
			return
		}
		t.State = n.State
	}
	a.put(n.ID, t)
	a.report(n.ID, t)
}

// report tells the gateway which message shows which state. A failure is retried
// on the next tick (the gateway keeps listing the notice until it is told).
func (a *approver) report(id string, t tracked) {
	code, _, err := a.gateway("POST", "/bot/notices/"+id+"/sent", map[string]any{"message_id": t.MessageID, "state": t.State})
	switch {
	case err != nil || code >= 500:
		log.Printf("approvals: report %s: %v (HTTP %d), will retry", id, err, code)
		return
	case code != http.StatusOK:
		log.Printf("approvals: gateway refused the report for %s (HTTP %d)", id, code)
	}
	if terminalStates[t.State] {
		a.drop(id)
	}
}

// prune forgets approvals the gateway stopped talking about long ago.
func (a *approver) prune() {
	a.mu.Lock()
	defer a.mu.Unlock()
	changed := false
	for id, t := range a.state {
		if t.FirstSeen > 0 && a.now().Sub(time.Unix(int64(t.FirstSeen), 0)) > maxStateAge {
			delete(a.state, id)
			changed = true
		}
	}
	if changed {
		a.save()
	}
}

// ── Telegram: messages ────────────────────────────────────────────────────

type button struct {
	Text         string `json:"text"`
	URL          string `json:"url,omitempty"`
	CallbackData string `json:"callback_data,omitempty"`
}

func keyboard(rows ...[]button) string {
	if rows == nil {
		rows = [][]button{}
	}
	raw, _ := json.Marshal(map[string]any{"inline_keyboard": rows})
	return string(raw)
}

// noticeMarkup is the keyboard of a state: Open and Deny while pending, Revoke
// while granted, none for an outcome.
func noticeMarkup(n notice) string {
	switch n.State {
	case "pending":
		row := []button{}
		if u, err := url.Parse(n.URL); err == nil && (u.Scheme == "https" || u.Scheme == "http") && u.Host != "" {
			row = append(row, button{Text: "Open", URL: n.URL})
		}
		row = append(row, button{Text: "Deny", CallbackData: "d:" + n.ID + ":" + n.Hash16})
		return keyboard(row)
	case "granted":
		return keyboard([]button{{Text: "Revoke", CallbackData: "r:" + n.ID + ":" + n.Hash16}})
	default:
		return keyboard()
	}
}

var stateHeads = map[string]string{
	"pending":   "🔐 <b>Approval needed</b>",
	"granted":   "✅ <b>Granted</b>",
	"used":      "✔️ <b>Used</b>",
	"denied":    "🚫 <b>Denied</b>",
	"revoked":   "↩️ <b>Revoked</b>",
	"expired":   "⌛ <b>Expired</b>",
	"cancelled": "🗑 <b>Cancelled</b>",
}

func noticeText(n notice) string {
	e := html.EscapeString
	var s strings.Builder
	s.WriteString(stateHeads[n.State])
	if via := strings.TrimSpace(n.DecidedVia); via != "" && n.State != "pending" {
		fmt.Fprintf(&s, " (%s)", e(via))
	}
	fmt.Fprintf(&s, "\n<b>%s</b>\n", e(n.Title))
	fmt.Fprintf(&s, "item %s · class %s\n", e(n.ItemID), e(n.Class))
	kind := "kind " + e(n.Kind)
	if p := n.Push; p != nil {
		kind += fmt.Sprintf(" · %s · %s", e(p.Repo), e(p.Branch))
		if p.Count != nil {
			kind += fmt.Sprintf(" · %s commit(s)", e(fmt.Sprint(p.Count)))
		}
	}
	s.WriteString(kind + "\n")
	if n.ExpiresAt != "" {
		fmt.Fprintf(&s, "expires %s\n", e(n.ExpiresAt))
	}
	short := n.ShortHash
	if short == "" {
		short = groups4(n.Hash16)
	}
	fmt.Fprintf(&s, "hash <code>%s</code>", e(short))
	return s.String()
}

func groups4(h string) string {
	var parts []string
	for len(h) > 4 {
		parts, h = append(parts, h[:4]), h[4:]
	}
	return strings.Join(append(parts, h), " ")
}

func (a *approver) sendNotice(n notice) (int64, error) {
	var res struct {
		MessageID int64 `json:"message_id"`
	}
	err := a.b.api("sendMessage", url.Values{
		"chat_id":                  {strconv.FormatInt(a.b.chatID, 10)},
		"text":                     {noticeText(n)},
		"parse_mode":               {"HTML"},
		"disable_web_page_preview": {"true"},
		"reply_markup":             {noticeMarkup(n)},
	}, &res)
	if err == nil && res.MessageID <= 0 {
		err = errors.New("sendMessage: no message_id in the answer")
	}
	return res.MessageID, err
}

func (a *approver) editNotice(n notice, mid int64) error {
	return a.b.api("editMessageText", url.Values{
		"chat_id":                  {strconv.FormatInt(a.b.chatID, 10)},
		"message_id":               {strconv.FormatInt(mid, 10)},
		"text":                     {noticeText(n)},
		"parse_mode":               {"HTML"},
		"disable_web_page_preview": {"true"},
		"reply_markup":             {noticeMarkup(n)},
	}, nil)
}

// editIsFinal: edits Telegram will never accept (the message is already as drawn,
// or was deleted by the owner). Retrying them every 15 s would help nobody.
func editIsFinal(err error) bool {
	var te *tgError
	if !errors.As(err, &te) || te.Code != http.StatusBadRequest {
		return false
	}
	d := strings.ToLower(te.Description)
	for _, s := range []string{"message is not modified", "message to edit not found", "message can't be edited", "message_id_invalid"} {
		if strings.Contains(d, s) {
			return true
		}
	}
	return false
}

func (b *Bot) answerCallback(id, text string) error {
	form := url.Values{"callback_query_id": {id}}
	if text != "" {
		form.Set("text", text)
	}
	return b.api("answerCallbackQuery", form, nil)
}

// ── callbacks ─────────────────────────────────────────────────────────────

// callback handles one button press. The query is ALWAYS answered, so the button
// stops spinning, but only a press from the owner, in the owner's chat, on the
// message statusbot stored for that approval, with that approval's hash, is
// passed on, and only as deny or revoke.
func (a *approver) callback(cq callbackQuery) {
	text := a.decide(cq)
	if err := a.b.answerCallback(cq.ID, text); err != nil {
		log.Print(err)
	}
}

func (a *approver) decide(cq callbackQuery) string {
	if cq.From.ID != a.owner || cq.Message == nil || cq.Message.Chat.ID != a.b.chatID {
		return "" // not the owner: say nothing
	}
	parts := strings.Split(cq.Data, ":")
	if len(parts) != 3 || (parts[0] != "d" && parts[0] != "r") || !idRe.MatchString(parts[1]) || !hashRe.MatchString(parts[2]) {
		return "Ignored"
	}
	action, want := "deny", "pending"
	if parts[0] == "r" {
		action, want = "revoke", "granted"
	}
	id, h16 := parts[1], parts[2]
	t, ok := a.get(id)
	if !ok || t.MessageID != cq.Message.MessageID || t.Hash16 != h16 {
		return "Ignored"
	}
	if t.State != want {
		return "Already decided"
	}
	code, raw, err := a.gateway("POST", "/bot/decision", map[string]string{"id": id, "action": action, "hash16": h16})
	if err != nil || code >= 500 {
		log.Printf("approvals: decision %s %s: %v (HTTP %d)", action, id, err, code)
		return "Not done: the gateway or legion is unreachable, try again"
	}
	var res struct {
		OK      bool   `json:"ok"`
		Ignored bool   `json:"ignored"`
		Error   string `json:"error"`
	}
	_ = json.Unmarshal(raw, &res)
	switch {
	case code == http.StatusOK && res.OK:
		// The outcome text arrives with the next poll; the buttons go now, so nobody presses twice.
		if err := a.b.api("editMessageReplyMarkup", url.Values{
			"chat_id":      {strconv.FormatInt(a.b.chatID, 10)},
			"message_id":   {strconv.FormatInt(t.MessageID, 10)},
			"reply_markup": {keyboard()},
		}, nil); err != nil && !editIsFinal(err) {
			log.Print(err)
		}
		if action == "deny" {
			return "Denied"
		}
		return "Revoked"
	case res.Ignored:
		return "Ignored"
	default:
		return "Not done: " + shortCode(res.Error)
	}
}

func shortCode(s string) string {
	if s == "" || len(s) > 40 {
		return "refused"
	}
	return strings.ReplaceAll(s, "_", " ")
}

// ── the digest line ───────────────────────────────────────────────────────

// approvalsLine is the one line the 08:00 digest gains; "" when approvals are off.
// It never fails: a gateway that is down or lacks /healthz/queue shows as "n/a".
func (b *Bot) approvalsLine() string {
	if b.cfg.Approvals.BotURL == "" {
		return ""
	}
	a, err := newApprover(b)
	if err != nil {
		return ""
	}
	return a.digestLine()
}

func (a *approver) digestLine() string {
	return "🔐 Approvals: " + a.pendingSummary() + " · Captures: " + a.queueSummary()
}

func (a *approver) pendingSummary() string {
	firstSeen := map[string]float64{}
	ns, err := a.fetch()
	owed := map[string]bool{}
	for _, n := range ns {
		owed[n.ID] = true
		if n.State == "pending" {
			firstSeen[n.ID] = n.FirstSeenAt
		}
	}
	a.mu.Lock()
	for id, t := range a.state {
		if !owed[id] && t.State == "pending" {
			firstSeen[id] = t.FirstSeen
		}
	}
	a.mu.Unlock()
	note := ""
	if err != nil {
		note = " (gateway unreachable, last known)"
		if len(firstSeen) == 0 {
			return "n/a (gateway unreachable)"
		}
	}
	if len(firstSeen) == 0 {
		return "none pending"
	}
	return fmt.Sprintf("%d pending%s%s", len(firstSeen), oldestAge(a.now(), firstSeen), note)
}

func oldestAge(now time.Time, firstSeen map[string]float64) string {
	oldest := 0.0
	for _, f := range firstSeen {
		if f > 0 && (oldest == 0 || f < oldest) {
			oldest = f
		}
	}
	if oldest == 0 {
		return ""
	}
	return " (oldest " + ago(now.Sub(time.Unix(int64(oldest), 0))) + ")"
}

// queueSummary reads /healthz/queue (ticket 51: 200 healthy, 503 alert, optional
// JSON with the counts). A missing endpoint (an older gateway) or a dead gateway
// leaves "n/a" instead of an error.
func (a *approver) queueSummary() string {
	code, raw, err := a.gateway("GET", "/healthz/queue", nil)
	switch {
	case err != nil:
		return "n/a (gateway unreachable)"
	case code == http.StatusNotFound:
		return "n/a"
	case code != http.StatusOK && code != http.StatusServiceUnavailable:
		return "n/a (HTTP " + strconv.Itoa(code) + ")"
	}
	var q struct {
		Queued     *int     `json:"queued"`
		Delivering *int     `json:"delivering"`
		Failed     *int     `json:"failed"`
		OldestAge  *float64 `json:"oldest_queued_age_seconds"`
	}
	if json.Unmarshal(raw, &q) != nil || (q.Queued == nil && q.Failed == nil) {
		if code == http.StatusServiceUnavailable {
			return "⚠️ queue alert"
		}
		return "queue ok"
	}
	n := 0
	if q.Queued != nil {
		n += *q.Queued
	}
	if q.Delivering != nil {
		n += *q.Delivering
	}
	s := "none queued"
	if n > 0 {
		s = fmt.Sprintf("%d queued", n)
		if q.OldestAge != nil {
			s += " (oldest " + ago(time.Duration(*q.OldestAge*float64(time.Second))) + ")"
		}
	}
	if q.Failed != nil && *q.Failed > 0 {
		s += fmt.Sprintf(" · ⚠️ %d failed", *q.Failed)
	} else if code == http.StatusServiceUnavailable {
		s += " · ⚠️ queue alert"
	}
	return s
}
