---
description: Run the session close in one pass — log, roadmap update, commit
disable-model-invocation: true
---

Close the current session. This command is the explicit close signal — run
the close to completion now, in one pass, with no further confirmation
pauses. Preconditions to verify (not redo): the work is committed-or-ready
and tests were green at the last "implementation complete" report.

1. **Verify state.** `npm run typecheck` + `npm test` green (use the WSL PATH
   prefix from CLAUDE.md). If either fails, stop and report — that's the only
   condition that interrupts a close.
2. **Write the log** at `sessions/NNN. Session Title — Log.md` with exactly
   these sections, each a few bullets at most:
   - **What was built/changed** (files + one-line why)
   - **Decisions made** (and what was deliberately deferred)
   - **State left behind** (test count, queue/log/branch state, anything
     half-open)
   - **Next session** (pointer to its prompt if drafted, or the one-line
     candidate scope)
3. **Update `sessions/roadmap.md`**: mark this session's entry done; adjust
   forward entries if this session changed the plan.
4. **Archive**: move the *previous* session's prompt + log
   (`sessions/(NNN-1). *.md`) into `sessions/archived/`. Skip silently if
   already archived. The current session's files stay until the next close.
5. **Commit** everything on the session branch (`session-NNN`). Never push to
   main, never merge — Al merges on his own cadence.
6. **Stop.** Do not begin the next session until Al opens it.
