# Testing

There are two kinds of tests. You run the suites from a checkout of this repo. The fault-injection
matrix (§12 of [the spec](specs/2026-10-30-design.md)) ran once on the real hosts. Results from each
build step's own checks are in [spec §14](specs/2026-10-30-design.md#14-spike-findings-2026-10-30).
The record of the fault-injection run has every measured time and the defects it found:
[records/2026-11-fault-injection-run.md](records/2026-11-fault-injection-run.md).

## CI

Two required checks run on every pull request. Their files are in `.github/workflows/`.

| Workflow | Proves |
|---|---|
| `lint.yml` | The YAML, the role, the shell scripts and the PowerShell scripts are clean. |
| `pr-issue-link.yml` | Every change is tied to an issue. |

What each one runs:
- **`lint.yml`:**
  - `yamllint --strict .`
  - `ansible-lint --strict` (profile `production`), from `ansible/`, after it installs
    `requirements.yml`.
  - `shellcheck` on every tracked `*.sh` file.
  - PSScriptAnalyzer (errors and warnings) on every `*.ps1` and `*.psm1` file.
- **`pr-issue-link.yml`:** the PR title must be a Conventional Commit. The body must say
  `Closes #<n>` for an open issue.

GitHub can't protect `main` on this private repo, so a convention keeps the rule. Merge only when
both checks are green. The `.githooks/pre-push` hook blocks direct pushes to `main`. Turn it on once
for each clone. In that clone's root folder, in any shell:

```bash
git config core.hooksPath .githooks
```

No CI job reaches Splunk, Cribl or the hosts. The suites below need them.

## The same lint on pi5

`scripts/bootstrap-pi.sh` installs yamllint and ansible-lint. It puts them in `~/.venvs/ansible-lint`
and links them into `~/.local/bin`. On pi5, with the Ansible venv on
([How to run a command](running-the-role.md#how-to-run-a-command)):

```bash
cd ~/homelab-splunk-missing-source && yamllint --strict .
cd ansible && ansible-lint --strict && ansible-playbook site.yml --syntax-check
```

## Test suites

| Suite | What it proves |
|---|---|
| `tests/spl/run.sh` | Every evaluator and macro case gives the expected status, cause and transitions. A full run adds more checks (below). |
| `tests/spl/dash.sh panels` | Every read-only data source of every view runs without errors. Each drilldown returns the field it passes on. |
| `tests/spl/dash.sh load [hosts]` | The Overview's searches load in under 3 s over a 300-host fixture, and match the generated mix. |
| `tests/spl/dash.sh writes` | Manage's writes work end to end on throwaway collections. |
| `tests/spl/dash.sh sync` | *DH Sync expected* upserts by `_key`, so rows it doesn't change stay as they were. |
| `tests/server/hl_server_app_test.sh` | The `server` helper handles `local/inputs.conf` correctly across a token rotation. |
| `tests/cribl/hl_cribl_config_test.sh` | The `cribl` helper's file swap works. |

These suites use throwaway objects named `dhtest_*`. They remove them on exit.

More detail on two of them:
- **`tests/spl/run.sh`** runs every case at a fixed clock.
- **`tests/spl/dash.sh writes`** covers each step of a Manage write:
  - the preview;
  - the confirmation;
  - the apply;
  - the admin log;
  - that a repeated or stale confirmation writes nothing;
  - the test-block command.

### Run `tests/spl/run.sh` and `dash.sh`

These suites need Splunk. Deploy the `hl_data_health` app first. Either run the role's `server` tag,
or run `tests/spl/dev-deploy.sh`. That script swaps the app in without restarting splunkd.

The suite reads the admin password from the file that `DH_PASS_FILE` names. It never prints the
password. In this lab, the default is `splunk-admin-password` in `~/wd2l-splunk/secrets/` on
HOMEPC. A full `run.sh` run also needs `node`.

On HOMEPC, in Git Bash, in the repo's root folder:

```bash
tests/spl/run.sh                # everything
tests/spl/run.sh '1*'           # some cases: a glob on the case folder name
tests/spl/run.sh --scale 300    # the generated scale case (300 hosts by default)
tests/spl/dash.sh panels
tests/spl/dash.sh load 300
tests/spl/dash.sh writes
tests/spl/dash.sh sync
```

Run one `dash.sh` mode at a time.

A full `run.sh` run also checks that:
- lookup names resolve (`lookup-names`, `lookup-names-static`);
- no search looks back past the indexes' retention (`retention-windows`);
- the saved searches' settings match `savedsearches.expect.csv`;
- the views pass a static check (`dash_check.py`);
- the committed Manage view equals the output of `tools/gen_dh_manage.js`;
- every macro, panel and input is documented in `docs/data-health/`, and nothing documented is gone.

Edit the generator, never `dh_manage.xml`. The suite uploads `dhtest_*` lookups and removes them. It
writes nothing to the KV store or to an index.

### Run `hl_server_app_test.sh`

Run it on Linux. Git Bash's `sha256sum` output breaks it. In the repo's root folder, on a Linux
host:

```bash
sh tests/server/hl_server_app_test.sh ansible/roles/homelab_splunk/files/hl_server_app.sh
```

It checks these things:
- Stale encrypted token copies are dropped.
- A retired `splunktcptoken` stanza is removed.
- Stanzas the role never shipped are left alone.
- Nothing changes when nothing changed.

### Run `hl_cribl_config_test.sh`

It needs only a POSIX shell, so it runs anywhere. This way runs it inside the Cribl container. On
HOMEPC, in PowerShell, in the repo's root folder:

```powershell
docker cp ansible/roles/homelab_splunk/files/hl_cribl_config.sh cribl:/tmp/
docker cp tests/cribl/hl_cribl_config_test.sh cribl:/tmp/
docker exec cribl sh /tmp/hl_cribl_config_test.sh /tmp/hl_cribl_config.sh
```

It uses a throwaway volume folder. It checks that:
- changes are reported and copied;
- the pushed-files record stays pending until it is committed;
- dropped files are deleted;
- files the role never pushed are kept;
- a retry after a revert copies the file back.

## Reading level of the docs

`tools/doc_grade.py` scores the prose of each current doc. The target is grade 8 or below, and 15
words a sentence or fewer. `docs/specs/` and `docs/records/` are exempt. It isn't in CI. On HOMEPC,
in PowerShell, in the repo's root folder:

```powershell
docker run --rm -v "${PWD}:/w:ro" -w /w python:3.14.10-slim python tools/doc_grade.py --worst 3
```
