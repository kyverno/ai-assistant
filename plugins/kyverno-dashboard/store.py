"""Dashboard state: one JSON file under the profile's Hermes home, shared by the agent-side tool
(tools.py) and the dashboard API (dashboard/plugin_api.py). Stdlib only."""

from __future__ import annotations

import fcntl
import json
import os
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List

SECTIONS = ("items", "views", "actions", "session")
KINDS = ("pr", "issue", "discussion")
MAX_ACTIONS = 500


def _home() -> Path:
    try:
        from hermes_constants import get_hermes_home

        return Path(get_hermes_home())
    except Exception:
        return Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")


def state_path() -> Path:
    return _home() / "kyverno-dashboard" / "state.json"


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def empty_state() -> Dict[str, Any]:
    return {"items": {}, "views": {}, "actions": [], "session": {}, "updated_at": None}


def load() -> Dict[str, Any]:
    try:
        with open(state_path(), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return empty_state()
    return {**empty_state(), **data}


@contextmanager
def _locked() -> Iterator[None]:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.parent / ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def _save(state: Dict[str, Any]) -> None:
    state["updated_at"] = now()
    path = state_path()
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False)
    os.replace(tmp, path)


def _check_key(key: Any) -> str:
    kind, _, num = str(key).partition(":")
    if kind not in KINDS or not num.strip():
        raise ValueError(f"item key must look like 'pr:123' / 'issue:45' / 'discussion:6', got {key!r}")
    return f"{kind}:{num.strip()}"


def _upsert_items(state: Dict[str, Any], data: Dict[str, Any]) -> int:
    items = data.get("items")
    if not isinstance(items, list) or not items:
        raise ValueError("data.items must be a non-empty array")
    for raw in items:
        if not isinstance(raw, dict):
            raise ValueError("each item must be an object")
        key = _check_key(raw.get("key"))
        cur = state["items"].get(key, {})
        # shallow merge: fields sent replace the old value, fields omitted keep it
        state["items"][key] = {**cur, **raw, "key": key, "updated_at": now()}
    return len(items)


def _set_view(state: Dict[str, Any], data: Dict[str, Any]) -> int:
    name = str(data.get("name") or "").strip()
    entries = data.get("entries")
    if not name or not isinstance(entries, list):
        raise ValueError("data needs a 'name' and an 'entries' array")
    clean: List[Dict[str, Any]] = []
    for e in entries:
        e = dict(e) if isinstance(e, dict) else {"key": e}
        e["key"] = _check_key(e.get("key"))
        clean.append(e)
    state["views"][name] = {
        "name": name,
        "title": data.get("title") or name,
        "description": data.get("description") or "",
        "groups": data.get("groups") or [],
        "entries": clean,
        "updated_at": now(),
    }
    return len(clean)


def _log_actions(state: Dict[str, Any], data: Dict[str, Any]) -> int:
    actions = data.get("actions")
    if not isinstance(actions, list) or not actions:
        raise ValueError("data.actions must be a non-empty array")
    for raw in actions:
        key = _check_key(raw.get("key"))
        entry = {
            "ts": now(),
            "key": key,
            "action": str(raw.get("action") or "").strip(),
            "summary": raw.get("summary") or "",
            "link": raw.get("link") or "",
        }
        if not entry["action"]:
            raise ValueError("each action needs an 'action' (e.g. approved, nudged, closed)")
        # the same action on the same item re-run is an update, not a second entry
        state["actions"] = [
            a for a in state["actions"]
            if not (a["key"] == key and a["action"] == entry["action"] and a["link"] == entry["link"])
        ]
        state["actions"].append(entry)
        item = state["items"].setdefault(key, {"key": key})
        item["acted"] = {"ts": entry["ts"], "action": entry["action"], "link": entry["link"]}
    state["actions"] = state["actions"][-MAX_ACTIONS:]
    return len(actions)


def _merge_session(state: Dict[str, Any], data: Dict[str, Any]) -> int:
    state["session"] = {**state["session"], **data}
    return len(data)


_HANDLERS = {
    "items": _upsert_items,
    "views": _set_view,
    "actions": _log_actions,
    "session": _merge_session,
}


def update(section: str, data: Dict[str, Any]) -> Dict[str, Any]:
    if section not in _HANDLERS:
        raise ValueError(f"section must be one of {SECTIONS}")
    if not isinstance(data, dict):
        raise ValueError("data must be an object")
    with _locked():
        state = load()
        n = _HANDLERS[section](state, data)
        _save(state)
    return {"section": section, "written": n, "items": len(state["items"]), "actions": len(state["actions"])}
