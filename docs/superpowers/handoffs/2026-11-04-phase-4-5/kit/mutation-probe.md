# Mutation probe (stress test ST-4) — how you work

You test whether a task's TripKit tests are strong enough to catch realistic bugs. You do NOT judge style
and you do NOT fix anything in the main repository.

You run in your own git worktree (your current directory). Never touch /home/user/jpy-27 itself, never
commit to a branch, never push. Swift: `export PATH=/opt/swift/usr/bin:$PATH`.

1. Read the task brief and the review package diff named in your dispatch, then the new/changed TripKit
   source files it lists.
2. Write 6–10 **mutants**: each one a small edit (1–5 lines) to TripKit *source* (never to tests) that
   encodes a bug a real developer could plausibly write here — off-by-one at a threshold, a `<` for `<=`,
   a wrong order of two side effects, a dropped guard, a state not reset, a re-check after `await`
   removed, a saturating op made trapping, a default that silently changes, the original bug the task
   fixes (named in the brief's "Vì sao"). Prefer mutants that change behaviour on inputs the tests could
   reach; skip mutants that cannot compile.
3. For each mutant: apply it, run the task's focused tests under a process timeout (`timeout 240 swift test --filter '<filter from dispatch>'`),
   record KILLED (a test failed — name it) or SURVIVED, then revert it (`git checkout -- <file>`). Build
   errors: fix the mutant or drop it; they do not count.
4. For each SURVIVED mutant decide: **equivalent** (no observable behaviour change — explain why) or
   **gap** (behaviour changes and no test notices — give the input that shows the difference and the
   assertion a test should make).
5. Leave the worktree clean (`git status --porcelain` empty). Scratch files go only in your own subfolder of the session scratchpad (named after your agent id); never run scripts you did not write there.

Final message (the report itself, no preamble):
- Table: # · file:line · mutation (one line) · bug class · KILLED by <test> | SURVIVED
- **Gaps** (each: mutant #, input that reveals it, suggested assertion) — these become Important findings
- **Equivalent survivors** with the reason
- Kill rate excluding equivalents
