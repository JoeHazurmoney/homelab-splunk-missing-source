# Handoff index: tasks drafted in the cloud, to finish on HOMEPC / pi5

Written 2026-11-01 by a cloud session that could reach GitHub but not HOMEPC, pi5 or the VMs.
Every remaining task (3b → 14) is **drafted, linted and pushed, but not run on a host**. One task per
branch, stacked in dependency order. Each branch has a note in this folder: what it adds, the
design choices the spec doesn't have yet, and the checks that finish it.

**Read the notes from the top branch, `feat/14-e2e`, which has all of them.**

## Where things stand

| Item | State |
|---|---|
| Task 3 (PR #32) | **merged** (`344e319`), with a review fix (the wd2l health check treated a missing record as fresh) |
| `main` | `344e319` |
| PR #31 (task 12e, Manage redesign) | open, green, reviewed statically: no blocking findings; needs a browser click-through and "Update branch" ([note](task-12e-manage.md)) |
| Tasks 3b–14 | drafted on the branches below |

## The stack (merge in this order; rebase or merge `main` into each one as the one below it lands)

| # | Branch | Issue | Note | Needs on the PC | Taylor's gate |
|---|---|---|---|---|---|
| 3b | `feat/3b-cribl` | #24 | [task-3b-cribl.md](task-3b-cribl.md) | Docker Desktop, Splunk | Cribl admin password into the vault; `docker pull` the image in a desktop session |
| 4 | `feat/4-uf-linux` | #5 | [task-4-uf-linux.md](task-4-uf-linux.md) | the VMs on, pi5 | — |
| 5 | `feat/5-uf-windows` | #6 | [task-5-uf-windows.md](task-5-uf-windows.md) | HOMEPC | **elevation on the PC** (MSI, groups, auditpol) |
| 6 | `feat/6-forwarder-apps` | #7 | [task-6-forwarder-apps.md](task-6-forwarder-apps.md) | all UF hosts | — (pin the TA sha256 first) |
| 7 | `feat/7-audit-rules` | #8 | [task-7-audit-rules.md](task-7-audit-rules.md) | the Linux hosts | — |
| 8 | `feat/8-udm-probe` | #9 | [task-8-udm-probe.md](task-8-udm-probe.md) | pi5, the UDM | **UniFi remote syslog → 192.168.1.27:5514/udp**; a firewall rule only if Docker's doesn't cover it |
| 10 | `feat/10-expected` | #11 | [task-10-expected.md](task-10-expected.md) | Splunk | keep or drop *DH Discover unregistered* (what it should write) |
| 12e | PR #31 | #30 | [task-12e-manage.md](task-12e-manage.md) | a browser | — |
| 11b | `feat/11b-dh-cribl` (contains #31) | #25 | [task-11b-dh-cribl.md](task-11b-dh-cribl.md) | Splunk, Cribl, a browser | — |
| 13 | `feat/13-docs` | #14 | [task-13-docs.md](task-13-docs.md) | — | — |
| 14 | `feat/14-e2e` | #15 | [task-14-e2e.md](task-14-e2e.md) | everything | the elevated test event log (row 13); the UniFi toggle (row 9) |

Tasks 4 and 5 don't depend on each other, and task 7 needs only task 4. The stack is one line only
so each branch builds on the last. If you verify them in another order, cherry-pick.

**PR per branch:** title as the note says, body `Closes #N` plus the note's check table with the
results. Squash-merge when `lint` and `pr-issue-link` are green (spec §10). Before a PR, run
`yamllint --strict .`, `cd ansible && ansible-lint --strict`, and `shellcheck $(git ls-files '*.sh')`;
for Splunk changes, also `tests/spl/run.sh` on HOMEPC.

## Decisions made while drafting (the spec doesn't have them yet; each note says where they go)

- **Cribl config goes into the volume as files** (Cribl 4.20's own layout under `cribl/`), with a
  manifest of what the role pushed, and a Cribl restart on change. Only the admin password and the
  lookup go through the API. Tunables are literals in those files; only the token is templated.
- **New tag `cribl_block`** sets or clears one block and **mirrors** the table into Splunk's
  `hl_ingest_block`. That answers the §7.2 open item (how Splunk learns the active blocks). The Manage
  form now shows this command (11b).
- **Cribl event breakers** (`breakers.yml`): TA_nix scripted output stays one event per run, with the
  current time; `linux_audit` breaks per record. Splunk no longer breaks UF data (§14.7 c).
- **All role input stanzas go in `local/`**: Splunk_TA_windows sorts before `hl_uf_windows_inputs`, and
  its default stanzas say `disabled = 1`.
- The input schema gained an optional **`hosts`** (the `probe.log` row is pi5-only).
- **`syslog_relay` is retired**, and `syslog_devices` (with a `port` and `source`) moved to
  `group_vars/splunk_server.yml`. `splunk_indexer` is now `hl_collector`.
- `50-hl-stig.rules` sorts before `wd2l.rules`, so `audit_rules` **rolls back** if wd2l's rule count changes.
- The expected list is rendered from **hostvars of every UF host**, so a host that is off stays expected.
- Data health: the "Cribl DOWN" cause; UF identity from the UF's own `_internal` (`dh_fwd_from_ufint`,
  `dh_uf_builds`); the Cribl tamper indicator (`dh_tamper_cribl`); `dh_probe_host`. Fixture cases 94–97.

## Things only Taylor decides

1. The Cribl admin password into the vault (3b).
2. Elevated changes on HOMEPC (5; the E2E test log in 14; a firewall rule in 8 only if needed).
3. The UniFi remote syslog setting (8; and toggling it in E2E row 9).
4. *DH Discover unregistered*: keep it (one summary record every 15 min) or drop it (10).
5. Host detail's "Agent ID (guid)": nothing provides it now. Drop the row, or add a scripted input that
   reads `instance.cfg` (11b).
6. Any force push, tag or release (spec §11).

## For the Obsidian handoff

Paste this as a new section of the project's handoff note (it runs past the usual 1000 characters on
purpose):

> ### 2026-11-01: cloud session drafted tasks 3b–14 (not yet run)
> **Merged:** task 3 (PR #32, `344e319`), with a fix to the wd2l health check (a missing record had
> counted as fresh). **Reviewed:** PR #31 (12e), statically: no blocking findings. It still needs
> a browser click-through and "Update branch".
>
> **Drafted, linted, pushed, not run on a host:** one branch per task, stacked:
> `feat/3b-cribl` → `feat/4-uf-linux` → `feat/5-uf-windows` → `feat/6-forwarder-apps` →
> `feat/7-audit-rules` → `feat/8-udm-probe` → `feat/10-expected` → (#31) → `feat/11b-dh-cribl` →
> `feat/13-docs` → `feat/14-e2e`. Each has a note in `docs/handoff/` (index: `docs/handoff/README.md`
> on `feat/14-e2e`) with its checks; the results go into new spec sections §14.9–§14.16.
>
> **Next, in order:**
> 1. Taylor: put `vault_hl_cribl_admin_password` in the vault on pi5, and `docker pull` the Cribl
>    image (by digest) in a desktop session.
> 2. Verify 3b; then 4 and 5 (5 needs Taylor's OK for elevation); then 6 (pin the TA sha256 first),
>    7, and 8 (Taylor repoints UniFi syslog to 192.168.1.27:5514/udp); then 10, #31, 11b, 13, 14.
> 3. One PR per branch (`Closes #N`), squash-merge when green, then rebase the next branch onto `main`.
>
> **Decisions to fold into the spec:**
> - Cribl config as files plus a manifest (API only for the password and the lookup).
> - New tag `cribl_block`, whose Splunk mirror answers §7.2's open item.
> - Cribl event breakers for TA_nix and auditd.
> - Role inputs always in `local/`.
> - The input schema's `hosts` field.
> - `syslog_relay` retired; `hl_collector`.
> - `audit_rules` rolls back if wd2l's rules drop.
> - The expected list built from all hostvars.
> - Data health: the "Cribl DOWN" cause; UF identity from `_internal`; the Cribl tamper indicator.
>
> **Open for Taylor:**
> - keep *DH Discover unregistered* or drop it;
> - the guid row on Host detail;
> - `wd2l_auditor` still has `run_collect` (wd2l's own config, untouched).
>
> **Licence:** the Splunk trial ends 2026-12-09 17:43 MST. Get the developer licence before then.

## Rules for Claude (unchanged, spec §10–§11)

- Work on `feat/<n>-<slug>` with one PR per task that closes its issue. Claude merges with a squash
  once `lint` and `pr-issue-link` are green. `main` is protected by convention only (`.githooks/pre-push`).
- Stop and ask Taylor before: elevation on the PC, the UDM's settings, vault secrets, any force push,
  tags or releases.
- Never edit wd2l's files, `[syslog]` props, `wd2l_audit` or pi5's `90-wd2l.conf`.
- Every PR that changes a macro or panel updates `docs/data-health/*.md`. The coverage check enforces it.
