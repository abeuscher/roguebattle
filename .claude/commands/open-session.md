---
description: Open a session from its prompt file and stop at the Open Gate
argument-hint: [session-number]
disable-model-invocation: true
---

Open session $ARGUMENTS.

Find `sessions/$ARGUMENTS. *.md` (match loosely on casing/spacing). That
prompt is the authority for this session.

Execute it as written: work the reading list in order, create the session
branch (`git checkout main && git checkout -b session-$ARGUMENTS`), then stop
at the Open Gate — post the one-paragraph orientation and wait for
confirmation. Do not pipeline past the gate into task work.

If no prompt file exists for session $ARGUMENTS, say so and stop. Do not
improvise one.
