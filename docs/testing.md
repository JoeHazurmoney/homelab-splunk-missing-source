# Testing

Two kinds of tests: suites you run from a checkout, and the fault-injection matrix (spec §12) run on
the real hosts. Results from each task's own checks are in [spec §14](specs/2026-10-30-design.md#14-spike-findings-2026-10-30).
The record of the fault-injection run, with every measured time and the defects it found, is
[records/2026-11-fault-injection-run.md](records/2026-11-fault-injection-run.md).

## CI

Two required checks run on every pull request (`.github/workflows/`). GitHub can't protect `main` on
this private repo, so the rule is kept by convention: merge only when both are green, and
`.githooks/pre-push` blocks direct pushes to `main` (enable it once per clone with
`git config core.hooksPath .githooks`).

| Workflow | Runs | Proves |
|---|---|---|
| `lint.yml` | `yamllint --strict .`; `ansible-lint --strict` (profile `production`) from `ansible/` after installing `requirements.yml`; `shellcheck` on every tracked `*.sh`; PSScriptAnalyzer (errors and warnings) on every `*.ps1` / `*.psm1` | the YAML, the role, the shell and PowerShell scripts are clean |
| `pr-issue-link.yml` | the PR title is a Conventional Commit, and the body says `Closes #<n>` for an open issue | every change is tied to an issue |

No CI job reaches Splunk, Cribl or the hosts; the suites below need them.

## The same lint on pi5

`scripts/bootstrap-pi.sh` installs yamllint and ansible-lint (`~/.venvs/ansible-lint`, linked into
`~/.local/bin`):

```bash
cd ~/homelab-splunk-missing-source && yamllint --strict .
cd ansible && ansible-lint --strict && ansible-playbook site.yml --syntax-check
```

## Test suites

| Suite | Where and how | Proves |
|---|---|---|
| `tests/spl/run.sh` | Git Bash on HOMEPC, with `hl_data_health` deployed (`--tags server`, or `tests/spl/dev-deploy.sh`, which swaps the app in without restarting splunkd). `tests/spl/run.sh` runs everything; `tests/spl/run.sh '1*'` some cases; `--scale [hosts]` the generated scale case (300 hosts by default). It reads the admin password from `DH_PASS_FILE` and never prints it. A full run needs `node`: it checks that the committed Manage view is the output of `tools/gen_dh_manage.js` (edit the generator, never `dh_manage.xml`) | every evaluator and macro fixture case under `tests/spl/cases/` gives the expected status, cause and transitions (run at a fixed clock). A full run also checks that lookup names resolve (`lookup-names`, `lookup-names-static`), that no search looks back past the indexes' retention (`retention-windows`), the saved searches' settings against `savedsearches.expect.csv`, the views statically (`dash_check.py`), and that every macro, panel and input is documented in `docs/data-health/` and nothing documented is gone. It uploads `dhtest_*` lookups and removes them; it writes nothing to KV or an index |
| `tests/spl/dash.sh panels` | as above | every read-only data source of every view runs without errors, and each drilldown returns the field it passes on |
| `tests/spl/dash.sh load [hosts]` | as above | the Overview's searches over the 300-host fixture load in under 3 s and match the generated mix |
| `tests/spl/dash.sh writes` | as above | Manage's writes end to end on throwaway collections: preview, confirm, apply, the admin log, that a repeated or stale confirmation writes nothing, and the test-block command |
| `tests/spl/dash.sh sync` | as above | *DH Sync expected*, as written, upserts by `_key`, so rows it doesn't change stay as they were |
| `tests/server/hl_server_app_test.sh` | on Linux: `sh tests/server/hl_server_app_test.sh ansible/roles/homelab_splunk/files/hl_server_app.sh` (Git Bash's `sha256sum` output breaks it) | the `server` helper's handling of `local/inputs.conf` across a token rotation: stale encrypted token copies dropped, a retired `splunktcptoken` stanza removed, stanzas the role never shipped left alone, no change when nothing changed |
| `tests/cribl/hl_cribl_config_test.sh` | anywhere with a POSIX sh, for example in the Cribl container: `docker cp` the helper and the test to `cribl:/tmp/`, then `docker exec cribl sh /tmp/hl_cribl_config_test.sh /tmp/hl_cribl_config.sh` | the `cribl` helper's file swap: changes reported and copied, the pushed-files record left pending until committed, dropped files deleted, files the role never pushed kept, a retry after a revert copies the file back. It uses a throwaway volume folder |

`tests/spl/` uses throwaway objects named `dhtest_*` and removes them on exit.

## Reading level of the docs

`tools/doc_grade.py` scores the prose of each current doc (target: grade 8 or below, 15 words a
sentence or fewer; `docs/specs/` and `docs/records/` are exempt). It isn't in CI. On HOMEPC, in
PowerShell, from the repo root:

```powershell
docker run --rm -v "${PWD}:/w:ro" -w /w python:3.14.10-slim python tools/doc_grade.py --worst 3
```
