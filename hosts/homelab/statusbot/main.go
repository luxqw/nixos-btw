// statusbot answers one Telegram chat about homelab: health, backups (3-2-1),
// logs, restarts from an allowlist, and a morning digest. Everything specific to
// the host comes from the JSON config that NixOS generates.
//
//	statusbot serve  CONFIG   long-poll Telegram and answer commands
//	statusbot digest CONFIG   send the digest once (run by a timer)
//	statusbot print  CONFIG   print the digest to stdout, for testing
package main

import (
	"encoding/json"
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
		return err
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

func run(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func pre(s string) string { return "<pre>" + html.EscapeString(s) + "</pre>" }

func (b *Bot) allowed(svc string) string {
	if svc == "" {
		return "which one? " + strings.Join(b.cfg.Services, ", ")
	}
	if !slices.Contains(b.cfg.Services, svc) {
		return "not on the list: " + strings.Join(b.cfg.Services, ", ")
	}
	return ""
}

func (b *Bot) logs(svc string) string {
	if msg := b.allowed(svc); msg != "" {
		return html.EscapeString(msg)
	}
	out, _ := run("journalctl", "-u", svc, "-n", "25", "--no-pager", "-o", "short-iso")
	return "<b>" + html.EscapeString(svc) + "</b>\n" + pre(out)
}

func (b *Bot) restart(svc string) string {
	if msg := b.allowed(svc); msg != "" {
		return html.EscapeString(msg)
	}
	if out, err := run("systemctl", "restart", svc); err != nil {
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
