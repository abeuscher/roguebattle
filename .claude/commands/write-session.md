---
description: Draft the next session's prompt strictly from the template
argument-hint: [session-number]
disable-model-invocation: true
---

Draft the prompt for session $ARGUMENTS.

Scope comes from, in priority order:
1. `sessions/roadmap.md` — if session $ARGUMENTS is pinned there, that entry
   is canonical.
2. What we've settled in this conversation.

If neither pins the scope, say what's missing and ask — do not invent scope.

Then read `sessions/template-session-prompt.md` in full. It is the canonical
format — do not infer the format from previous sessions' files. Before
writing, confirm in one short list: the template's required sections, and the
scope you're about to build to.

Write `sessions/$ARGUMENTS. {Session Title}.md`, filling every section
(write "none" rather than deleting headings). Keep it short — this is a small
project; a session prompt should fit on one screen or two.
