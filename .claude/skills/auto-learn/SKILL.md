---
name: auto-learn
description: >
  Recursive self-improvement skill. Triggers automatically whenever Claude: encounters an
  error and fixes it, discovers a new API behavior or constraint, finds a better pattern
  than what's in the existing skills, or receives a correction from the user. Also invoke
  this skill proactively at the end of any non-trivial session. It persists learnings to
  the right place so every future session starts smarter. Triggers on: "remember this",
  "add this to learnings", "update the skill", "we just discovered that...", end of any
  session where something new was found.
---

# auto-learn — Recursive Self-Improvement

This skill ensures every discovery, fix, and correction feeds back into the system
so future sessions never repeat the same mistakes or re-derive the same patterns.

## When to invoke

Invoke this skill **inline, immediately** when any of these happen:

| Trigger | Target |
|---------|--------|
| An error occurred and you fixed it | `learnings/pitfalls.md` |
| A new API behavior was discovered | `learnings/pitfalls.md` or `learnings/patterns.md` |
| A pattern worked better than expected | `learnings/patterns.md` |
| User corrected your approach | `memory/` + possibly the relevant skill |
| A skill's instructions were wrong or incomplete | The skill's `SKILL.md` |
| A new choice field / table / flow ID was created | `CLAUDE.md` |
| User stated a preference about how to work | `memory/feedback_*.md` |

Don't wait until the end of the session — write the learning as soon as you know it.

## Decision tree: where does the learning go?

```
Is it a trap / error / API quirk?
  → learnings/pitfalls.md

Is it a pattern that produced a better result?
  → learnings/patterns.md

Is it a user preference or working style correction?
  → memory/feedback_<topic>.md
  AND possibly the relevant skill if it affects instructions

Is it authoritative project-level data (IDs, table names, choice values)?
  → CLAUDE.md (the canonical source of truth)

Is the skill's instructions demonstrably wrong or missing something critical?
  → Update the skill's SKILL.md directly
```

## How to write a pitfall entry

```markdown
### <Short title that describes the symptom>
- **Symptom**: What the error or wrong behavior looks like
- **Root cause**: Why it happens
- **Fix**: Exact code or command that resolves it
- **Documented in**: Which files also reference this
```

## How to write a pattern entry

```markdown
### <Short title of the pattern>
Why this pattern is preferred over the alternative.
<code example>
```

## How to update a skill

1. Read the current `SKILL.md` for the relevant skill
2. Find the section that needs updating (or add a new "Known pitfalls" section at the bottom)
3. Edit inline — do not rewrite sections that are correct
4. Keep the addition focused: one learning = one entry, no padding

## How to update memory

```markdown
---
name: <topic>
description: <one-line summary>
type: feedback
---

<rule>

**Why:** <reason the user gave or the incident that revealed this>
**How to apply:** <when this guidance kicks in>
```

## Checking for duplicates

Before writing, do a quick check:
```powershell
grep -i "keyword" learnings/pitfalls.md learnings/patterns.md
```
If a similar entry exists, update it rather than adding a duplicate.

## After writing

- Confirm to the user: "I've added this to `learnings/pitfalls.md` → <title>."
- If a skill was updated: "I've updated `.claude/skills/<name>/SKILL.md` with this pattern."
- No need to re-explain the learning — one line is enough.

## Periodic skill reinforcement

At the start of a session involving a skill (e.g., creating a new flow), glance at
`learnings/pitfalls.md` for entries tagged to that skill. If learnings exist that
aren't reflected in the skill's instructions yet, update the skill before starting the task.

This is the recursive loop: learnings → skill improvements → better outcomes → more learnings.
