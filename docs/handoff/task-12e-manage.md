# Handoff: task 12e — PR #31, the Manage redesign

Issue #30 · PR #31 · branch `feat/12e-manage-redesign` (by the earlier session; untouched here).

## Review in this session (2026-11-01, static only)

- CI green (`lint`, `pr-issue-link`); GitHub reports it **mergeable**, but it was opened on `main` at
  `587f20c`, before task 3 merged. A trial merge with today's `main` (`344e319`) is clean.
- `node tools/gen_dh_manage.js` reproduces the committed `dh_manage.xml` byte for byte, so the view and
  its generator agree.
- `tests/spl/dash_check.py check` (the views' static rules) and `docs` (the coverage check) pass.
- yamllint clean.
- **No blocking findings** in a static read. One note: spec §7.8 says "a write runs only on submit".
  #31 has no Submit button: picking the form's own **Confirm** choice is the submit (Studio applies
  canvas inputs at once). `dash_check` enforces one Confirm per form, cascading resets and no shared
  tokens. That matches issue #30's approved design, but update §7.8's wording when merging.
- Its own open item: **not yet checked in a browser**.

## Finish it (on HOMEPC)

1. Click **Update branch** on PR #31 (or merge `main` into it). No conflicts are expected.
2. Deploy the branch to the dev Splunk: `tests/spl/dev-deploy.sh`. Then run `tests/spl/run.sh` (the PR
   says 80 passed) and `tests/spl/dash.sh writes panels load`.
3. **Browser click-through** (the PR's open item), Manage tab by tab:
   - Each tab's inputs sit above their own preview; nothing is written on load.
   - Fill in a mute: the preview appears; **Confirm** offers exactly one "Apply: …" line, and picking it
     writes once ("Done: …"). Change any input: Confirm resets.
   - Reload the page with the same URL: "Nothing written: …" (the token no longer fits).
   - Idle panels show the "fill in the form" text, not Splunk's warning icons.
   - Times show their zone.
   - Admin log tab: the changes appear.
4. Update spec §7.8's "write runs only on submit" (see above), then merge #31 (squash).
5. **Then task 11b** (`feat/11b-dh-cribl`) already contains #31 plus the test-block change. Its diff
   shrinks once #31 is on `main`. 11b's Test blocks tab supersedes #31's (it shows a command, no Apply).
