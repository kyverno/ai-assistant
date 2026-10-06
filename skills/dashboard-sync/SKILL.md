---
name: dashboard-sync
description: "Push what was just presented, and every confirmed action, to the maintainer's dashboard tab with update_dashboard."
version: 0.1.0
author: Suhaani Agarwal, Hermes Agent
license: MIT
platforms: [linux, macos, windows]
---

# dashboard-sync Skill

The maintainer's dashboard (`hermes -p kyverno dashboard`, Kyverno tab) shows
queues, triage results, Discussions and confirmed actions as linked items with
verdicts and related PRs/issues, so nothing has to be scrolled back to or
copy-pasted from the session. The other skills call this one at the points they
name. `update_dashboard`'s own description carries the field shapes.

## When to Use

- Right after presenting a PR queue, review brief, stale-PR list, issue triage,
  or Discussions summary.
- Right after a GitHub write the maintainer confirmed and that landed
  (approve, request changes, comment, label, nudge, close, assign, raise an
  issue), and after a defer.

## Procedure: push a presentation

1. `section: "items"` — one item per PR, issue, or Discussion you showed:
   `key`, `title`, `url`, `status`, state chips, `verdict` (`action` + `reason`),
   `needs_you`, `threads`, and `related` for every related PR/issue — plural,
   competing PRs included. Include `draft` when a comment awaits confirmation.
   Send what you told the maintainer, condensed — same verdict, same reasons —
   not raw fetch output.
2. `section: "views"` — the ordered list the maintainer saw, items sent first:

   | Presentation | `name` | `groups` / `entries[].group` |
   |---|---|---|
   | PR queue | `queue` | one group per tier, `tier` set on each entry |
   | Stale / author-blocked PRs | `stale` (`stale-<milestone>` when scoped) | the verdict: rescue, decide, close |
   | Issue triage | `triage` | priority bands, most urgent first |
   | Discussions | `discussions` | needs a decision, active, informational |

   A single-PR brief sends items only.
3. `section: "session"` — `focus`, `milestone`, `milestone_due`, `gate`,
   `counts` whenever they are known.

## Procedure: log an action

Only after the write landed, never for a draft:

1. `section: "actions"` — `key`, a one-word `action` (approved, commented,
   nudged, closed, labeled, deferred), a one-line `summary`, and `link` to the
   comment, review, or issue the write produced.
2. Re-send the item: `draft` emptied, `verdict.action` set to `done` when the
   decision resolved it.

## Pitfalls

- A confirmed action is logged once per write. Re-sending the same one updates
  it in place.
- `related` states each edge from this item's side (`closed-by`, `supersedes`,
  `competes`); send one side — the reverse is derived.
- If `update_dashboard` fails, finish the answer and say so in one line.
- Mention the push in a short clause ("on your dashboard"), not a paragraph.

## Verification

- After a presentation, the Kyverno tab lists every item named in the answer
  with the same verdict.
- After a confirmed action, the Activity tab shows it once, with a link.
