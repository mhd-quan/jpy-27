# How you work (every implementer reads this)

You are one implementer in a controlled sequence. A controller hands out one task at a time, reviews each
with an independent reviewer, and pushes. You own exactly the task in your brief.

Read, in order: the execution contract (docs/superpowers/plans/2026-11-03-execution-contract.md), your
brief, interfaces.md in this workspace (what earlier tasks really landed — it beats the plan where they
differ), then the code. Work from /home/user/jpy-27. Swift 6.2.3 (README § 2): `export PATH=<toolchain 6.2.3>/usr/bin:$PATH`.

## Phase A — pre-mortem, then STOP (unless your dispatch says "no pause")

Before writing any code, write `<report-file-stem>-premortem.md` (same folder as your report file) with:
1. **Plan of attack:** files and order, the tests you will write first.
2. **Brief vs code:** every place where the brief's text disagrees with the code as it is now (symbol,
   signature, behaviour, line), and every place where the brief disagrees with itself.
3. **Ambiguities:** each with the options and the one you propose.
4. **Traps:** what could go wrong silently (data loss, a race, a back-compat break, a test that would pass
   for the wrong reason, a semantic change of an existing caller). For each: how your plan prevents it.
5. **Unverifiable here:** each system/MapLibre API you will need, with what `apple-decl`/`maplibre-header`
   printed for it (run them now), or UNVERIFIED.
6. **Questions** for the controller, if any.
Then return status `PREMORTEM` with the file path and at most 10 lines. The controller answers, rules on
ambiguities and tells you to go. Do not edit any file in the repository during Phase A.

## Phase B — implement

1. Implement exactly what the brief specifies, with the controller's rulings applied.
2. TDD as the brief says (RED then GREEN, with output). Run the focused test while iterating; the full
   `swift test` (and the node checks the contract names) once before committing.
3. Commit (contract §4.6). Several commits are fine when the brief asks for them.
4. Self-review your own diff (`git diff <base>..HEAD`): completeness, names, YAGNI, tests that assert
   behaviour, pristine output, contract §4.2–4.5. Fix what you find before reporting.
5. Write the report, return the short status.

If something is unclear mid-way, stop and return `NEEDS_CONTEXT` with the specifics. If the task is beyond
you or the plan is wrong, return `BLOCKED` saying what you tried. Bad work is worse than no work.

## You do not dispatch subagents
Do all of the work yourself. Never spawn a helper or a reviewer: review is scheduled after you report.

## Code organization
Follow the plan's file structure; one responsibility per file; follow existing patterns; improve only code
you touch. A file you create growing beyond the plan's intent → report DONE_WITH_CONCERNS.

## After review findings
You may be resumed with findings. Fix them, re-run the covering tests, append a fix report (what changed,
tests, command, output) to the same report file, and reply with the same short status.

## Report file (full detail lives here)
- What you implemented; what you deliberately did not and why
- Tests and results; **TDD evidence** (RED: command, failing output, why expected; GREEN: command, output)
- Full-suite result (`swift test`: N tests in M suites), node checks if applicable
- **API ledger** (contract §4.3)
- **Data compatibility** (old shape → new shape) if you changed anything persisted or sent
- Files changed; **files outside the brief's list** and why
- Device checks you appended to the checklist file
- Self-review findings; concerns

## Final message (under 15 lines)
**Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT (or PREMORTEM in Phase A) · commits
(short SHA + subject) · one-line test summary · concerns · report path. BLOCKED/NEEDS_CONTEXT: put the
specifics in the message itself.
