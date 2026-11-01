# Handoff: task 13 — documentation

Issue #14 · branch `feat/13-docs`, **stacked on `feat/11b-dh-cribl`** (so the docs describe the whole
drafted stack) · drafted in a cloud session on 2026-11-01.

**State:** spec §9's list is drafted from the drafted code, not from a running system. Each page has to be
checked against what tasks 3b–11b find on the real hosts.

| Document (spec §9) | State |
|---|---|
| `README.md` | rewritten: what and why, quick start, a table of common jobs, the documents |
| `docs/architecture.md` | new: the diagram, inside Cribl, ports, indexes, what is collected |
| `docs/running-the-role.md` | new: the one-time setup (the six steps, the vault, the packages), the deploy tags in order, day-to-day tags, toggles, removal with each contract, troubleshooting |
| `docs/data-health-design.md` | new: spec §2 and §7 in short, Cribl as the relay, tamper indicators, the test block, porting to production |
| `docs/data-health/dashboards.md`, `macros.md` | already living documents (12d); updated by 10 and 11b |
| `docs/runbook-missing-data.md` | new: every cause the Overview shows, in the evaluator's order: meaning, what to check, what to do |
| `docs/testing.md` | task 14 (its branch has the template) |
| the Obsidian handoff and log | see `docs/handoff/README.md` → "For the Obsidian handoff" |

## Finish it

1. After each of tasks 3b–11b, fix whatever its checks changed. Most likely to move:
   - the vault keys and setup step 5 (the Cribl image pull);
   - the `cribl_block` command line;
   - the contract wording in `running-the-role.md` §4;
   - the cause texts in `runbook-missing-data.md`, which must match `dh_eval_cause_text`
     (grep for each one).
2. **The done-when test:** "someone can run the role from the docs alone." Read `README.md` →
   `running-the-role.md` as a new user would, on a clean checkout, and follow the steps exactly. Fix
   every step that needed knowledge from outside the docs.
3. Links: `grep -o '](.*\.md[^)]*)' -r README.md docs/*.md` and check that each target exists.
4. PR: `docs: README, architecture, running the role, data-health design and runbook (task 13)`,
   `Closes #14`. Merge after 11b.
