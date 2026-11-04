// statusbot answers one Telegram chat about homelab: health, backups (3-2-1),
// logs, restarts from an allowlist, and a morning digest. Everything specific to
// the host comes from the JSON config that NixOS generates.
//
//	statusbot serve  CONFIG   long-poll Telegram and answer commands
//	statusbot digest CONFIG   send the digest once (run by a timer)
//	statusbot print  CONFIG   print the digest to stdout, for testing
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"time"
)

type Repo struct {
	Medium    string `json:"medium"`
	Repo      string `json:"repo,omitempty"`
	Heartbeat string `json:"heartbeat,omitempty"`
}

type Class struct {
	Name  string   `json:"name"`
	Live  string   `json:"live"`
	Repos []string `json:"repos"`
	// Copies is how many copies count as enough; 0 means the usual 3.
	Copies int `json:"copies,omitempty"`
}

type Config struct {
	PasswordFile string          `json:"passwordFile"`
	Repos        map[string]Repo `json:"repos"`
	Classes      []Class         `json:"classes"`
	BackupUnits  []string        `json:"backupUnits"`
	Services     []string        `json:"services"`
	Disks        []string        `json:"disks"`
	Gatus        string          `json:"gatus"`
	Scrutiny     string          `json:"scrutiny"`
	FlakeLock    string          `json:"flakeLock"`
	MaxAgeHours  float64         `json:"maxAgeHours"`
}

type Bot struct {
	cfg    Config
	token  string
	chatID int64
	http   *http.Client
}

func main() {
	if len(os.Args) != 3 {
		log.Fatal("usage: statusbot serve|digest|print CONFIG")
	}
	raw, err := os.ReadFile(os.Args[2])
	if err != nil {
		log.Fatal(err)
	}
	var cfg Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		log.Fatal(err)
	}
	if os.Args[1] == "print" {
		fmt.Println((&Bot{cfg: cfg}).digest())
		return
	}
	chatID, err := strconv.ParseInt(os.Getenv("TELEGRAM_CHAT_ID"), 10, 64)
	if err != nil || os.Getenv("TELEGRAM_TOKEN") == "" {
		log.Fatal("TELEGRAM_TOKEN and TELEGRAM_CHAT_ID must be set")
	}
	b := &Bot{cfg: cfg, token: os.Getenv("TELEGRAM_TOKEN"), chatID: chatID, http: &http.Client{Timeout: 70 * time.Second}}

	switch os.Args[1] {
	case "serve":
		b.serve()
	case "digest":
		if err := b.send(b.digest()); err != nil {
			log.Fatal(err)
		}
	default:
		log.Fatalf("unknown mode %q", os.Args[1])
	}
}

// ── Telegram ──────────────────────────────────────────────────────────────

func (b *Bot) api(method string, form url.Values, out any) error {
	resp, err := b.http.PostForm("https://api.telegram.org/bot"+b.token+"/"+method, form)
	if err != nil {
		// *url.Error carries the request URL, which contains the bot token.
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err
		}
		return fmt.Errorf("%s: %w", method, err)
	}
	defer resp.Body.Close()
	var body struct {
		OK          bool            `json:"ok"`
		Description string          `json:"description"`
		Result      json.RawMessage `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return err
	}
	if !body.OK {
		return fmt.Errorf("%s: %s", method, body.Description)
	}
	if out != nil {
		return json.Unmarshal(body.Result, out)
	}
	return nil
}

func (b *Bot) send(text string) error {
	if len(text) > 4000 {
		text = text[:4000] + "\n…"
	}
	return b.api("sendMessage", url.Values{
		"chat_id":    {strconv.FormatInt(b.chatID, 10)},
		"text":       {text},
		"parse_mode": {"HTML"},
	}, nil)
}

var commands = [][2]string{
	{"status", "health: units, checks, disks, temps, updates"},
	{"backups", "3-2-1 report per kind of data"},
	{"backup", "start every backup job now"},
	{"logs", "last journal lines of a service: /logs immich-server"},
	{"restart", "restart an allowlisted service: /restart jellyfin"},
	{"digest", "the morning summary, now"},
}

func (b *Bot) serve() {
	var list []map[string]string
	for _, c := range commands {
		list = append(list, map[string]string{"command": c[0], "description": c[1]})
	}
	cmds, _ := json.Marshal(list)
	if err := b.api("setMyCommands", url.Values{"commands": {string(cmds)}}, nil); err != nil {
		log.Print(err)
	}

	offset := 0
	for {
		var updates []struct {
			UpdateID int `json:"update_id"`
			Message  *struct {
				Chat struct {
					ID int64 `json:"id"`
				} `json:"chat"`
				Text string `json:"text"`
			} `json:"message"`
		}
		err := b.api("getUpdates", url.Values{
			"offset":          {strconv.Itoa(offset)},
			"timeout":         {"50"},
			"allowed_updates": {`["message"]`},
		}, &updates)
		if err != nil {
			log.Print(err)
			time.Sleep(10 * time.Second)
			continue
		}
		for _, u := range updates {
			offset = u.UpdateID + 1
			if u.Message == nil || u.Message.Chat.ID != b.chatID {
				continue
			}
			if err := b.send(b.handle(u.Message.Text)); err != nil {
				log.Print(err)
			}
		}
	}
}

func (b *Bot) handle(text string) string {
	fields := strings.Fields(text)
	if len(fields) == 0 {
		return b.help()
	}
	cmd := strings.TrimPrefix(strings.SplitN(fields[0], "@", 2)[0], "/")
	arg := ""
	if len(fields) > 1 {
		arg = fields[1]
	}
	switch cmd {
	case "status":
		return b.status()
	case "backups":
		return b.backups()
	case "backup":
		return b.backupNow()
	case "logs":
		return b.logs(arg)
	case "restart":
		return b.restart(arg)
	case "digest":
		return b.digest()
	default:
		return b.help()
	}
}

func (b *Bot) help() string {
	var s strings.Builder
	s.WriteString("<b>homelab</b>\n")
	for _, c := range commands {
		fmt.Fprintf(&s, "/%s — %s\n", c[0], html.EscapeString(c[1]))
	}
	return s.String()
}

// ── commands ──────────────────────────────────────────────────────────────

// run kills a command that hangs, so one stuck SFTP or journal read can't
// freeze the poll loop. WaitDelay covers children (ssh under restic) that keep
// the output pipe open after the kill.
func run(name string, args ...string) (string, error) {
	return runFor(90*time.Second, name, args...)
}

func runFor(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.WaitDelay = 5 * time.Second
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// pre keeps the newest lines of s, well under Telegram's 4096 limit: send's
// own cut would drop the closing tag and Telegram rejects the message. It
// escapes first and trims after, on a line boundary, so neither an entity nor
// a tag is ever cut in half. A newest line too long for that is cut by runes
// before escaping; no rune escapes to more than 5 bytes.
func pre(s string) string {
	const limit = 3000
	esc := html.EscapeString(s)
	if len(esc) > limit {
		tail := esc[len(esc)-limit-1:]
		if i := strings.IndexByte(tail, '\n'); i >= 0 && i+1 < len(tail) {
			esc = tail[i+1:]
		} else {
			r := []rune(s)
			esc = html.EscapeString(string(r[len(r)-limit/5:]))
		}
		esc = "…\n" + esc
	}
	return "<pre>" + esc + "</pre>"
}

// unit resolves svc against the allowlist, also by instance name ("pumpkin"
// for container@pumpkin), and returns the unit or else the reply to send.
func (b *Bot) unit(svc string) (string, string) {
	if svc == "" {
		return "", "which one? " + strings.Join(b.cfg.Services, ", ")
	}
	if slices.Contains(b.cfg.Services, svc) {
		return svc, ""
	}
	for _, s := range b.cfg.Services {
		if strings.HasSuffix(s, "@"+svc) {
			return s, ""
		}
	}
	return "", "not on the list: " + strings.Join(b.cfg.Services, ", ")
}

func (b *Bot) logs(svc string) string {
	svc, msg := b.unit(svc)
	if msg != "" {
		return html.EscapeString(msg)
	}
	out, _ := run("journalctl", "-u", svc, "-n", "25", "--no-pager", "-o", "short-iso")
	return "<b>" + html.EscapeString(svc) + "</b>\n" + pre(out)
}

func (b *Bot) restart(svc string) string {
	svc, msg := b.unit(svc)
	if msg != "" {
		return html.EscapeString(msg)
	}
	// Longer than a slow stop (90 s for several units) plus the start.
	if out, err := runFor(5*time.Minute, "systemctl", "restart", svc); err != nil {
		return "❌ restart failed\n" + pre(out)
	}
	time.Sleep(3 * time.Second)
	state, _ := run("systemctl", "is-active", svc)
	return fmt.Sprintf("🔄 %s: %s", html.EscapeString(svc), html.EscapeString(state))
}

func (b *Bot) backupNow() string {
	args := append([]string{"start", "--no-block"}, b.cfg.BackupUnits...)
	if out, err := run("systemctl", args...); err != nil {
		return "❌ couldn't start\n" + pre(out)
	}
	return "▶️ started: " + html.EscapeString(strings.Join(b.cfg.BackupUnits, ", ")) +
		"\nAsk /backups in a while; failures arrive here on their own."
}

func (b *Bot) digest() string {
	return "☀️ <b>Good morning</b>\n\n" + b.status() + "\n\n" + b.backups()
}
