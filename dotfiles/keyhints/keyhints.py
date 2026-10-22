"""Mod+F1 cheat sheet.

Prints one line per bind for fzf: umbriel and zellij binds parsed from their
configs, Claude skills from their SKILL.md frontmatter, and the hand-written
entries in <app>.toml next to this file. A curated entry with the same keys as
a parsed one replaces its description; `star = true` puts it on top.
"""

import json
import os
import re
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
ORDER = ["system", "umbriel", "zellij", "shell", "nvim", "yazi", "lazygit", "claude", "skills"]

YELLOW, DIM, CYAN, RESET = "\033[33m", "\033[2m", "\033[36m", "\033[0m"


def pretty(key):
    for a, b in (("Mod+", "Super+"), ("Alt ", "Alt+"), ("Ctrl ", "Ctrl+")):
        key = key.replace(a, b)
    return key


def umbriel():
    try:
        with open(CONFIG / "umbriel/config.toml", "rb") as f:
            binds = tomllib.load(f).get("keybinds", {})
    except OSError:
        return
    for key, act in binds.items():
        if isinstance(act, dict):
            act = act.get("action", "")
        if "Wheel" in key or key.startswith("XF86"):
            continue
        if act.startswith("spawn:"):
            act = "run " + act[6:].split(";")[0][:60]
        yield key, act.replace("-", " ")


def zellij():
    try:
        text = (CONFIG / "zellij/config.kdl").read_text()
    except OSError:
        return
    for m in re.finditer(r'bind "(Alt [^"]+)" \{\s*(\w+)\s*"?([^";]*)', text):
        yield m[1], f"{m[2]} {m[3]}".strip()


def frontmatter(path):
    text = path.read_text(errors="replace")
    if not text.startswith("---"):
        return {}
    block = text.split("---", 2)[1]
    meta, key = {}, None
    for line in block.splitlines():
        m = re.match(r"^([\w-]+):\s*(.*)$", line)
        if m:
            key, val = m[1], m[2].strip()
            meta[key] = "" if val in (">", "|", ">-", "|-") else val.strip("'\"")
        elif key and line.startswith((" ", "\t")):
            meta[key] = (meta[key] + " " + line.strip()).strip()
    return meta


def skill_dirs():
    for d in sorted((HOME / ".claude/skills").glob("*/")):
        if (d / "SKILL.md").exists():
            yield d, None
    try:
        settings = json.loads((HOME / ".claude/settings.json").read_text())
        installed = json.loads((HOME / ".claude/plugins/installed_plugins.json").read_text())
    except (OSError, ValueError):
        return
    for plugin, enabled in settings.get("enabledPlugins", {}).items():
        entries = installed.get("plugins", {}).get(plugin) if enabled else None
        if not entries:
            continue
        root = Path(entries[0]["installPath"])
        name = plugin.split("@")[0]
        try:
            listed = json.loads((root / ".claude-plugin/plugin.json").read_text()).get("skills")
        except (OSError, ValueError):
            listed = None
        dirs = [root / s for s in listed] if listed else sorted((root / "skills").glob("*/"))
        for d in dirs:
            if (d / "SKILL.md").exists():
                yield d, name


def skills():
    for d, plugin in skill_dirs():
        meta = frontmatter(d / "SKILL.md")
        desc = meta.get("description", "")
        first = re.split(r"(?<=\.)\s", desc, maxsplit=1)[0]
        desc = first if len(first) >= 25 else desc
        if len(desc) > 100:
            desc = desc[:99] + "…"
        if plugin:
            desc = f"{desc} ({plugin})"
        yield "/" + meta.get("name", d.name), desc


PARSED = {"umbriel": umbriel, "zellij": zellij, "skills": skills}


def entries():
    rows = {}
    for app in ORDER:
        for keys, desc in PARSED.get(app, lambda: [])():
            rows[(app, keys)] = {"app": app, "keys": keys, "desc": desc, "star": False}
        path = HERE / f"{app}.toml"
        if path.exists():
            with open(path, "rb") as f:
                for e in tomllib.load(f).get("key", []):
                    row = rows.setdefault((app, e["keys"]), {"app": app, "keys": e["keys"], "desc": ""})
                    row["desc"] = e.get("desc", row["desc"])
                    row["star"] = e.get("star", False)
    return rows.values()


def main():
    rows = sorted(entries(), key=lambda r: (not r["star"], ORDER.index(r["app"])))
    for r in rows:
        star = f"{YELLOW}★{RESET}" if r["star"] else f"{DIM}·{RESET}"
        print(f"{star} {CYAN}{r['app']:<8}{RESET} {pretty(r['keys']):<26} {DIM if not r['star'] else ''}{r['desc']}{RESET}")


if __name__ == "__main__":
    main()
