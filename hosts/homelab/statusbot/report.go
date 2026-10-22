package main

import (
	"encoding/json"
	"fmt"
	"html"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// ── /status ───────────────────────────────────────────────────────────────

func (b *Bot) status() string {
	var s strings.Builder
	s.WriteString("<b>Status</b>\n")

	failed, _ := run("systemctl", "list-units", "--state=failed", "--plain", "--no-legend", "--no-pager")
	var units []string
	for _, line := range strings.Split(failed, "\n") {
		if f := strings.Fields(line); len(f) > 0 {
			units = append(units, f[0])
		}
	}
	if len(units) == 0 {
		s.WriteString("✅ no failed units\n")
	} else {
		fmt.Fprintf(&s, "❌ failed: %s\n", html.EscapeString(strings.Join(units, ", ")))
	}

	if down, err := b.gatusDown(); err != nil {
		fmt.Fprintf(&s, "⚠️ gatus: %s\n", html.EscapeString(err.Error()))
	} else if len(down) == 0 {
		s.WriteString("✅ all checks green\n")
	} else {
		fmt.Fprintf(&s, "❌ down: %s\n", html.EscapeString(strings.Join(down, ", ")))
	}

	for _, d := range b.cfg.Disks {
		var st syscall.Statfs_t
		if syscall.Statfs(d, &st) != nil {
			continue
		}
		total := float64(st.Blocks) * float64(st.Bsize)
		free := float64(st.Bavail) * float64(st.Bsize)
		used := 100 * (1 - free/total)
		mark := "💾"
		if used > 90 {
			mark = "⚠️"
		}
		fmt.Fprintf(&s, "%s %s %.0f%% used, %.0f GB free\n", mark, d, used, free/1e9)
	}

	s.WriteString(b.smart())
	s.WriteString(machine())
	s.WriteString(b.drift())
	return s.String()
}

func getJSON(u string, out any) error {
	c := &http.Client{Timeout: 10 * time.Second}
	resp, err := c.Get(u)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("%s: HTTP %d", u, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (b *Bot) gatusDown() ([]string, error) {
	var eps []struct {
		Name    string `json:"name"`
		Results []struct {
			Success bool `json:"success"`
		} `json:"results"`
	}
	if err := getJSON(b.cfg.Gatus+"/api/v1/endpoints/statuses", &eps); err != nil {
		return nil, err
	}
	var down []string
	for _, e := range eps {
		if n := len(e.Results); n > 0 && !e.Results[n-1].Success {
			down = append(down, e.Name)
		}
	}
	return down, nil
}

func (b *Bot) smart() string {
	var body struct {
		Data struct {
			Summary map[string]struct {
				Device struct {
					Name   string `json:"device_name"`
					Status int    `json:"device_status"`
				} `json:"device"`
				Smart struct {
					Temp int `json:"temp"`
				} `json:"smart"`
			} `json:"summary"`
		} `json:"data"`
	}
	if err := getJSON(b.cfg.Scrutiny+"/api/summary", &body); err != nil {
		return "⚠️ scrutiny: " + html.EscapeString(err.Error()) + "\n"
	}
	var parts []string
	ok := true
	for _, d := range body.Data.Summary {
		mark := ""
		if d.Device.Status != 0 {
			ok, mark = false, " FAILING"
		}
		parts = append(parts, fmt.Sprintf("%s %d°C%s", d.Device.Name, d.Smart.Temp, mark))
	}
	icon := "✅"
	if !ok {
		icon = "❌"
	}
	return fmt.Sprintf("%s SMART: %s\n", icon, strings.Join(parts, " · "))
}

func readFloat(path string) float64 {
	raw, _ := os.ReadFile(path)
	f, _ := strconv.ParseFloat(strings.Fields(string(raw) + " 0")[0], 64)
	return f
}

func machine() string {
	cpu := 0.0
	names, _ := filepath.Glob("/sys/class/hwmon/hwmon*/name")
	for _, n := range names {
		raw, _ := os.ReadFile(n)
		if strings.TrimSpace(string(raw)) == "coretemp" {
			cpu = readFloat(filepath.Join(filepath.Dir(n), "temp1_input")) / 1000
		}
	}
	load := readFloat("/proc/loadavg")
	up := time.Duration(readFloat("/proc/uptime")) * time.Second

	mem := map[string]float64{}
	raw, _ := os.ReadFile("/proc/meminfo")
	for _, line := range strings.Split(string(raw), "\n") {
		if f := strings.Fields(line); len(f) >= 2 {
			mem[strings.TrimSuffix(f[0], ":")], _ = strconv.ParseFloat(f[1], 64)
		}
	}
	used := 0.0
	if mem["MemTotal"] > 0 {
		used = 100 * (1 - mem["MemAvailable"]/mem["MemTotal"])
	}
	return fmt.Sprintf("🌡 CPU %.0f°C · load %.2f · RAM %.0f%% · up %s\n", cpu, load, used, ago(up))
}

// drift compares the nixpkgs homelab runs with the one pinned on GitHub main,
// so "flake updated but never deployed" shows up before an app breaks.
func (b *Bot) drift() string {
	raw, err := os.ReadFile("/run/current-system/nixos-version")
	if err != nil {
		return ""
	}
	parts := strings.Split(strings.TrimSpace(string(raw)), ".")
	if len(parts) < 4 {
		return ""
	}
	deployedRev := parts[3]
	deployed, err := time.Parse("20060102", parts[2])
	if err != nil {
		return ""
	}

	var lock struct {
		Nodes map[string]struct {
			Locked struct {
				Rev          string `json:"rev"`
				LastModified int64  `json:"lastModified"`
			} `json:"locked"`
		} `json:"nodes"`
	}
	if err := getJSON(b.cfg.FlakeLock, &lock); err != nil {
		return "⚠️ can't read flake.lock from GitHub\n"
	}
	pinned := lock.Nodes["nixpkgs"].Locked
	if strings.HasPrefix(pinned.Rev, deployedRev) {
		return fmt.Sprintf("✅ deployed nixpkgs %s matches GitHub\n", deployed.Format("2006-01-02"))
	}
	days := int(time.Unix(pinned.LastModified, 0).Sub(deployed).Hours() / 24)
	if days <= 0 {
		return fmt.Sprintf("ℹ️ deployed nixpkgs %s differs from GitHub's (not older)\n", deployed.Format("2006-01-02"))
	}
	return fmt.Sprintf("⚠️ homelab is %d days behind flake.lock on GitHub: run deploy-homelab\n", days)
}

// ── /backups ──────────────────────────────────────────────────────────────

type snapshotAge struct {
	age time.Duration
	err string
}

func (b *Bot) repoAge(name string) snapshotAge {
	r, ok := b.cfg.Repos[name]
	if !ok {
		return snapshotAge{err: "not set up"}
	}
	if r.Heartbeat != "" {
		raw, err := os.ReadFile(r.Heartbeat)
		if err != nil {
			return snapshotAge{err: "never reported"}
		}
		ts, err := strconv.ParseInt(strings.TrimSpace(string(raw)), 10, 64)
		if err != nil {
			return snapshotAge{err: "bad heartbeat"}
		}
		return snapshotAge{age: time.Since(time.Unix(ts, 0))}
	}
	out, err := run("restic", "-r", r.Repo, "--password-file", b.cfg.PasswordFile,
		"snapshots", "--latest", "1", "--json", "--no-lock", "-q")
	if err != nil {
		return snapshotAge{err: "unreadable"}
	}
	var snaps []struct {
		Time time.Time `json:"time"`
	}
	if json.Unmarshal([]byte(out), &snaps) != nil || len(snaps) == 0 {
		return snapshotAge{err: "no snapshots"}
	}
	latest := snaps[0].Time
	for _, s := range snaps {
		if s.Time.After(latest) {
			latest = s.Time
		}
	}
	return snapshotAge{age: time.Since(latest)}
}

func ago(d time.Duration) string {
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 48*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

func (b *Bot) backups() string {
	maxAge := time.Duration(b.cfg.MaxAgeHours * float64(time.Hour))
	ages := map[string]snapshotAge{}
	for _, c := range b.cfg.Classes {
		for _, r := range c.Repos {
			if _, done := ages[r]; !done {
				ages[r] = b.repoAge(r)
			}
		}
	}

	var s strings.Builder
	s.WriteString("<b>Backups</b> (3 copies · 2 media · 1 offsite)\n")
	for _, c := range b.cfg.Classes {
		copies, offsite := 1, false
		media := map[string]bool{c.Live: true}
		var detail []string
		for _, r := range c.Repos {
			a := ages[r]
			switch {
			case a.err != "":
				detail = append(detail, r+" "+a.err)
			case a.age > maxAge:
				detail = append(detail, r+" "+ago(a.age)+" old")
			default:
				detail = append(detail, r+" "+ago(a.age))
				copies++
				medium := b.cfg.Repos[r].Medium
				media[medium] = true
				offsite = offsite || medium == "offsite"
			}
		}
		icon := "✅"
		if copies < 3 || len(media) < 2 || !offsite {
			icon = "⚠️"
		}
		off := "no offsite"
		if offsite {
			off = "offsite"
		}
		fmt.Fprintf(&s, "%s <b>%s</b>: %d copies · %d media · %s\n    %s\n",
			icon, html.EscapeString(c.Name), copies, len(media), off,
			html.EscapeString(strings.Join(detail, " · ")))
	}
	return s.String()
}
