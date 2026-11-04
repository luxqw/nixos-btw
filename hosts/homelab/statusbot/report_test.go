package main

import (
	"encoding/json"
	"html"
	"strings"
	"testing"
)

func TestNixpkgsFollowsRootInput(t *testing.T) {
	raw := `{
		"root": "root",
		"nodes": {
			"nixpkgs":   {"locked": {"rev": "claude-code-pin", "lastModified": 1}},
			"nixpkgs_4": {"locked": {"rev": "root-pin", "lastModified": 2}},
			"root": {"inputs": {"nixpkgs": "nixpkgs_4"}}
		}
	}`
	var lock flakeLock
	if err := json.Unmarshal([]byte(raw), &lock); err != nil {
		t.Fatal(err)
	}
	pin, ok := lock.nixpkgs()
	if !ok || pin.Rev != "root-pin" || pin.LastModified != 2 {
		t.Fatalf("got %+v, %v; want the root input's pin", pin, ok)
	}
}

func TestNixpkgsMissing(t *testing.T) {
	var lock flakeLock
	if err := json.Unmarshal([]byte(`{"root":"root","nodes":{"root":{"inputs":{}}}}`), &lock); err != nil {
		t.Fatal(err)
	}
	if _, ok := lock.nixpkgs(); ok {
		t.Fatal("expected no nixpkgs")
	}
}

func TestPreFitsAndStaysBalanced(t *testing.T) {
	// Every line escapes to several times its length, as journal lines
	// full of quotes and angle brackets do.
	line := "<a href=\"x\"> & 'y' </a>\n"
	got := pre(strings.Repeat(line, 500))
	if len(got) > 3100 {
		t.Fatalf("pre is %d bytes, over the budget", len(got))
	}
	if !strings.HasPrefix(got, "<pre>…\n") || !strings.HasSuffix(got, "</pre>") {
		t.Fatalf("tags unbalanced: %q ... %q", got[:12], got[len(got)-12:])
	}
	body := strings.TrimSuffix(strings.TrimPrefix(got, "<pre>…\n"), "</pre>")
	want := html.EscapeString(line)
	for _, l := range strings.SplitAfter(body, "\n") {
		if l != "" && l != want {
			t.Fatalf("line cut mid-way: %q", l)
		}
	}
}

func TestPreShortInputIsUntouched(t *testing.T) {
	if got := pre("a < b"); got != "<pre>a &lt; b</pre>" {
		t.Fatalf("got %q", got)
	}
}

func TestPreSingleHugeLine(t *testing.T) {
	got := pre(strings.Repeat("<", 5000))
	if len(got) > 3100 || !strings.HasSuffix(got, "</pre>") {
		t.Fatalf("got %d bytes", len(got))
	}
	if !strings.Contains(got, "&lt;") {
		t.Fatalf("newest line was dropped: %q", got)
	}
}
