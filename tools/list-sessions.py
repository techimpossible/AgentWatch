#!/usr/bin/env python3
"""Enumerate every Claude Code session across all profiles → JSON.

Reads the same local files AgentWatch reads (no network, no AgentWatch needed):
  - profiles: ~/.claude ("default") + every ~/.config/claude-* + $CLAUDE_CONFIG_DIR
  - one record per transcript:  <profile>/projects/<dir>/<sessionId>.jsonl

Each record carries safe metadata + the first user prompt + a profile-aware
resume command and agentwatch:// link — ready to map to one Asana task each.

Usage:
  python3 tools/list-sessions.py            # JSON array to stdout
  python3 tools/list-sessions.py --md       # markdown table instead
"""
import os, sys, json, glob, datetime
from urllib.parse import quote

HOME = os.path.expanduser("~")

def profiles():
    roots = [(os.path.join(HOME, ".claude"), "default")]
    for d in sorted(glob.glob(os.path.join(HOME, ".config", "claude-*"))):
        roots.append((d, os.path.basename(d)[len("claude-"):]))
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    if env:
        for part in env.split(":"):
            part = part.strip()
            if part:
                roots.append((part, os.path.basename(part.rstrip("/"))))
    # de-dupe by path, keep first label
    seen, out = set(), []
    for path, label in roots:
        rp = os.path.realpath(path)
        if rp not in seen:
            seen.add(rp); out.append((path, label))
    return out

def first_prompt_and_cwd(jsonl_path, max_lines=40, max_len=200):
    cwd, prompt = None, None
    try:
        with open(jsonl_path, "r", encoding="utf-8", errors="ignore") as f:
            for i, line in enumerate(f):
                if i > max_lines or (cwd and prompt):
                    break
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if not cwd and obj.get("cwd"):
                    cwd = obj["cwd"]
                if not prompt and obj.get("type") == "user":
                    c = obj.get("message", {}).get("content")
                    if isinstance(c, str):
                        prompt = c
                    elif isinstance(c, list):
                        prompt = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
    except Exception:
        pass
    if prompt:
        prompt = " ".join(prompt.split())[:max_len]
    return cwd, prompt

def shquote(s):
    # POSIX single-quote quoting: wrap in '...' and escape any internal ' as '\''
    # so copy-pasted commands can't be hijacked by $(...) or backticks in a path.
    return "'" + str(s).replace("'", "'\\''") + "'"

def resume_command(profile, profile_dir, session_id, cwd):
    cwd = cwd or HOME
    base = f"cd {shquote(cwd)} && claude --resume {shquote(session_id)}"
    if profile == "default":
        return base
    # Non-default profiles need CLAUDE_CONFIG_DIR so `claude` finds the session.
    return f"cd {shquote(cwd)} && CLAUDE_CONFIG_DIR={shquote(profile_dir)} claude --resume {shquote(session_id)}"

def agentwatch_url(profile, session_id, cwd):
    q = f"profile={quote(profile)}&session={quote(session_id)}&cwd={quote(cwd or HOME)}"
    return f"agentwatch://resume?{q}"

def collect():
    records = []
    for path, label in profiles():
        for jsonl in glob.glob(os.path.join(path, "projects", "*", "*.jsonl")):
            sid = os.path.splitext(os.path.basename(jsonl))[0]
            cwd, prompt = first_prompt_and_cwd(jsonl)
            project = os.path.basename(cwd) if cwd else os.path.basename(os.path.dirname(jsonl))
            mtime = datetime.datetime.fromtimestamp(os.path.getmtime(jsonl)).astimezone().isoformat()
            records.append({
                "profile": label,
                "project": project,
                "sessionId": sid,
                "cwd": cwd,
                "lastModified": mtime,
                "firstPrompt": prompt,
                "resumeCommand": resume_command(label, path, sid, cwd),
                "agentwatchURL": agentwatch_url(label, sid, cwd),
            })
    records.sort(key=lambda r: r["lastModified"], reverse=True)
    return records

def main():
    recs = collect()
    if "--md" in sys.argv:
        print(f"| Profile | Project | Last activity | First prompt | Resume |")
        print(f"|---|---|---|---|---|")
        for r in recs:
            fp = (r["firstPrompt"] or "").replace("|", "\\|")[:80]
            print(f'| {r["profile"]} | {r["project"]} | {r["lastModified"][:16]} | {fp} | `{r["resumeCommand"]}` |')
    else:
        print(json.dumps(recs, indent=2))

if __name__ == "__main__":
    main()
