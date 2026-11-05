"""Mod+F1 cheat sheet.

Prints one line per bind for fzf: umbriel and zellij binds parsed from their
configs, Claude skills from their SKILL.md frontmatter, and the hand-written
entries in <app>.toml next to this file. A curated entry with the same keys as
a parsed one replaces its description; `star = true` puts it on top. Hyprland's
binds are Lua, which is not parsed: hyprland.toml lists all of them.
"""

import json
import os
import re
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
ORDER = ["system", "umbriel", "niri", "hyprland", "zellij", "shell", "nvim", "yazi", "lazygit", "claude", "skills"]

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


def kdl_nodes(text):
    """Nodes of a KDL document: {name, args, props, children, off}. Comments are
    skipped, `/-` marks the next node off, quoted and raw strings are values."""
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r":
            i += 1
        elif c == "\n":
            toks.append(("nl", ""))
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif text.startswith("/-", i):
            toks.append(("off", ""))
            i += 2
        elif c in "{};":
            toks.append((c, c))
            i += 1
        elif c == '"':
            j, out = i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    j += 1
                out.append(text[j])
                j += 1
            toks.append(("str", "".join(out)))
            i = j + 1
        elif (m := re.match(r'r(#*)"', text[i:i + 40])):
            end = '"' + m[1]
            j = text.find(end, i + m.end())
            j = n if j < 0 else j
            toks.append(("str", text[i + m.end():j]))
            i = j + len(end)
        else:
            j = i
            while j < n and text[j] not in ' \t\r\n{};"':
                j += 1
            toks.append(("word", text[i:j]))
            i = j
    pos = 0

    def level():
        nonlocal pos
        found, off = [], False
        while pos < len(toks):
            kind, val = toks[pos]
            if kind in ("nl", ";"):
                pos += 1
            elif kind == "}":
                pos += 1
                return found
            elif kind == "off":
                off = True
                pos += 1
            else:
                node = {"name": val, "args": [], "props": {}, "children": [], "off": off}
                off = False
                pos += 1
                while pos < len(toks) and toks[pos][0] not in ("nl", ";", "{", "}"):
                    kind, val = toks[pos]
                    pos += 1
                    if kind == "word" and val.endswith("=") and pos < len(toks) and toks[pos][0] in ("str", "word"):
                        node["props"][val[:-1]] = toks[pos][1]
                        pos += 1
                    elif kind == "word" and "=" in val:
                        k, _, v = val.partition("=")
                        node["props"][k] = v
                    else:
                        node["args"].append(val)
                if pos < len(toks) and toks[pos][0] == "{":
                    pos += 1
                    node["children"] = level()
                found.append(node)
        return found

    return level()


def kdl_binds(path, seen=None):
    """The enabled binds of a niri config and everything it includes, in niri's
    order: a later bind on the same key replaces an earlier one."""
    seen = set() if seen is None else seen
    try:
        path = Path(path).expanduser().resolve()
        text = path.read_text()
    except OSError:
        return {}
    if path in seen:
        return {}
    seen.add(path)
    binds = {}
    for node in kdl_nodes(text):
        if node["off"]:
            continue
        if node["name"] == "include" and node["args"]:
            target = Path(node["args"][0]).expanduser()
            binds.update(kdl_binds(target if target.is_absolute() else path.parent / target, seen))
        elif node["name"] == "binds":
            for bind in node["children"]:
                if bind["off"]:
                    continue
                binds[bind["name"]] = bind
    return binds


def niri():
    for key, bind in kdl_binds(CONFIG / "niri/config.kdl").items():
        actions = [a for a in bind["children"] if not a["off"]]
        if not actions or "Wheel" in key or key.startswith("XF86") or bind["props"].get("hotkey-overlay-hidden") == "true":
            continue
        act = actions[0]
        if bind["props"].get("hotkey-overlay-title"):
            desc = bind["props"]["hotkey-overlay-title"]
        elif act["name"] == "spawn":
            desc = "run " + " ".join([Path(act["args"][0]).name] + act["args"][1:])[:60] if act["args"] else "run"
        elif act["name"] == "spawn-sh":
            desc = "run " + (act["args"][0].split(";")[-1].strip()[:60] if act["args"] else "script")
        else:
            desc = " ".join([act["name"]] + act["args"]).replace("-", " ")
        yield key, desc


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


PARSED = {"umbriel": umbriel, "niri": niri, "zellij": zellij, "skills": skills}

# Each compositor lists its own binds; a plain terminal shows both.
COMPOSITORS = {"umbriel", "niri", "hyprland"}


def entries():
    rows = {}
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    for app in ORDER:
        if app in COMPOSITORS and desktop in COMPOSITORS and app != desktop:
            continue
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
