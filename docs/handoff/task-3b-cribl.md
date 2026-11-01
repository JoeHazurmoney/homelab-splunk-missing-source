# Handoff: task 3b — Cribl Stream (`cribl` / `cribl_remove` / `cribl_block`)

Issue #24 · branch `feat/3b-cribl` (from `main` at `344e319`) · drafted in a cloud session on
2026-11-01 without access to HOMEPC or pi5.

**State:** written, `yamllint --strict` + `ansible-lint --strict` (production) + `shellcheck` clean,
`--syntax-check` OK. The Cribl config and `compose.yml` were rendered locally with dummy secrets
and parse. The in-container helper was exercised against a fake volume. **Nothing has run against
Cribl, Docker Desktop or Splunk.** Every API call and file path below that the spike didn't prove is
marked *unverified* and has a check.

## What the branch adds

| Path | What |
|---|---|
| `cribl/local/cribl/inputs.yml` | `in_splunk_tcp` (9997, token), `CriblLogs` → `cribl`, `CriblMetrics` → `cribl_metrics`, `in_cribl_audit` (File Monitor) |
| `cribl/local/cribl/outputs.yml` | `out_splunk` → `wd2l-splunk:9997` over `hl-net`, token, `enableACK: true`, `maxS2Sversion: v4`, `systemFields: []`, PQ on |
| `cribl/local/cribl/pipelines/route.yml` | `r_cribl_self`, `r_syslog_devices` (→ `pl_test_block`), `r_uf` (→ `pl_test_block`), `r_default` (catch-all, unchanged) |
| `cribl/local/cribl/pipelines/pl_test_block/conf.yml` | the spike's Code + Drop block, as tested |
| `cribl/local/cribl/pipelines/pl_syslog_pre/conf.yml` | pre-processing pipeline on every device source: `_time = Date.now()/1000` |
| `cribl/local/cribl/cribl.yml` | `workers.count: 2` (the 60 MB/day licence cost) |
| `cribl/data/lookups/hl_ingest_block.csv` | the empty block table (seed) |
| `roles/.../templates/cribl/compose.yml.j2` | image by digest, `hostname: cribl`, volume `hl-cribl-data`, `hl-net` external, ports 9997/tcp, one UDP port per device, `127.0.0.1:9000` |
| `roles/.../templates/cribl/device_inputs.yml.j2` | one syslog source per `syslog_devices` entry (`in_<name>_syslog`), merged into `inputs.yml` |
| `roles/.../files/hl_cribl_config.sh` | in-container helper: swaps files into `$CRIBL_VOLUME_DIR/local/cribl`, keeps a manifest of what it pushed |
| `tasks/cribl.yml` | preconditions → marker → compose up → health → **admin password first** → render + swap config → restart Cribl if changed → check the loaded objects → seed the lookup → Cribl's data in Splunk → self-test per device → state file → marker |
| `tasks/cribl_block.yml` | `--tags cribl_block`: set/clear one block through the lookups API, prune expired rows, **mirror the table into Splunk's `hl_server_base/lookups/hl_ingest_block.csv`** |
| `tasks/cribl_remove.yml` | marker → `compose down --volumes` → leftovers by name → compose folder → state → contract |
| `tasks/marker.yml` | shared HEC marker (`action`, `target_host`, `by`, `run_id`), posted from pi5. Task 4 reuses it |
| `tasks/server_restart.yml` | optional `hl_cribl_hold_on_splunk_restart`: `docker pause cribl` around a splunkd restart (off by default) |
| `inventory/group_vars/splunk_server.yml` | `syslog_devices` moved here from `syslog_relay.yml`, with `port: 5514` and `source: syslog:udm` |
| `vault.yml.example`, `scripts/bootstrap-pi.sh` | `vault_hl_cribl_admin_password`; bootstrap now reports missing vault keys |

### Design choices the local session should know (not in the spec yet)

1. **Config goes in as files, not through the API.** The role renders the repo's YAML and swaps it
   into `$CRIBL_VOLUME_DIR/local/cribl/`, then restarts Cribl (lost nothing in the spike, §14.7 a).
   Idempotence compares against the role's own record of what it pushed (`local/.hl_pushed.manifest`),
   not the live file, because Cribl may rewrite a file itself (it encrypts tokens). A UI edit therefore
   isn't reverted by the next run. That's deliberate: the Cribl tamper indicator catches it (§7.6).
   Only the **admin password** and the **lookup** go through the API.
2. **Tunables are literals in the Cribl files** (`maxS2Sversion`, `pqMaxSize`, `workers.count`).
   Only the token is templated. Change Cribl by editing `cribl/`, which is the point of config as code.
3. **Variables are flat `hl_cribl_*`**, not a `cribl:` dict as §5.2 says, to match the rest of the
   role and its argument specs.
4. **New tag `cribl_block`** (never). It answers the §7.2 open item: it writes Cribl's table *and* a
   Splunk-side mirror, which task 11b can read for the "test block until hh:mm" label. The Manage
   form should show this command (task 11b).
5. **The self-test** sends `HL_CRIBL_SELFTEST run=<id>` to each device port after a change and waits for it
   with the device's host/index/sourcetype/source, and `_time` within 60 s of `_indextime`. It
   makes the UDM look alive for one threshold. Turn it off with `-e hl_cribl_selftest=false`.
6. **`r_default`** sends anything unmatched to Splunk unchanged, so a new source is never dropped
   silently. Drop it if you'd rather see nothing unexpected.

## Before running (Taylor's gates, in order)

1. **Vault (gate, spec §11):** on pi5, `cd ~/…/ansible && ansible-vault edit inventory/group_vars/all/vault.yml`
   and add `vault_hl_cribl_admin_password: "<24+ random chars>"`
   (`python3 -c 'import secrets; print(secrets.token_urlsafe(24))'`).
2. **Image:** in a **desktop** PowerShell on HOMEPC (not over SSH):
   `docker pull cribl/cribl@sha256:cb2b2e32933e492f439b5825b0c36f420df2fa986fe36d5f31fce6755190eb71`.
3. Sync the branch to pi5 (`scripts/sync-to-pi.ps1`), and check `--tags server_network` reports no change.

## Run

```bash
cd ansible
ansible-playbook site.yml --tags cribl --limit homepc -v      # first run: changed
ansible-playbook site.yml --tags cribl --limit homepc         # second run: expect changed=0
```

## Checks (each one is part of "done"; record the results in spec §14.9)

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | `docker compose` works over SSH | the "Bring the container up" task | container `cribl` running, `docker ps` shows the 3 ports | if compose is missing over SSH, replace the task with `docker run` using the same settings (the compose file is the reference) |
| 2 | **Admin password API** (*unverified*: `GET`/`PATCH /system/users/admin`) | the "Set the admin password" task; then log in to `http://127.0.0.1:9000` with the vault password | `HL_PW=set` on the first run, `HL_PW=ok` on the second | set it in the UI once (the first login forces a change). Open DevTools → Network, copy the request the UI sends, and fix the task to match |
| 3 | **Plaintext tokens in pushed YAML** (§11 row 3b) | after the restart: `docker exec cribl sh -c 'grep -n token $CRIBL_VOLUME_DIR/local/cribl/*.yml'` | out_splunk connects: Cribl's own logs arrive (the play waits for them). Note whether Cribl rewrote the token encrypted | if out_splunk is refused (Splunk `splunkd.log`: token), push the two tokens through the API instead (`PATCH /system/outputs/out_splunk`, `/system/inputs/in_splunk_tcp`) and drop `authToken`/`authTokens` from the files. The UF side is proven in task 4 |
| 4 | **Worker count** (*unverified*: a local `cribl.yml` holding only `workers` is merged) | Cribl UI → Monitoring → System, or `docker exec cribl ps -ef \| grep -c 'cribl.*worker'`; licence: `index=_internal source=*license_usage.log type=Usage idx=cribl earliest=-1h \| stats sum(b)` | 2 worker processes; ≈ 12 MB/day (about a fifth of the spike's 60) | if Cribl ignores it or other settings vanish, set *Worker Processes* in the UI, copy the resulting `local/cribl/cribl.yml` into the repo, and redeploy |
| 5 | `systemFields: []` drops `cribl_pipe` | the play asserts it | no `cribl_pipe` in `index=cribl` | try `systemFields: [""]`, or a final Eval that removes `cribl_pipe` in each route's pipeline |
| 6 | **Splunk-restart loss** (§14.7 g), **run after task 4** (needs a real UF) | on wd2l-recv: `sudo -u splunkfwd /opt/splunkforwarder/bin/splunk add monitor /tmp/hl-seq.log -index linux -sourcetype hl:seqtest`; `i=0; while :; do i=$((i+1)); echo "seq=$i $(date -Is)" >> /tmp/hl-seq.log; sleep 1; done &`; after 60 s, `--tags server -e hl_server_force_restart=true` (this path honours the hold option); after 3 min, `index=linux sourcetype=hl:seqtest \| rex "seq=(?<s>\d+)" \| stats count dc(s) min(s) max(s)` | `max-min+1 == dc` (no gap), duplicates allowed | a) `maxS2Sversion: v4` alone (the branch default); b) `hl_cribl_hold_on_splunk_restart: true`; c) `enableACK: false`. Keep the first that shows no gap; else document the gap in §13 and in the E2E row. **Clean up:** `splunk remove monitor /tmp/hl-seq.log`, kill the loop, `rm /tmp/hl-seq.log` |
| 7 | **Audit File Monitor path** (*unverified* with `CRIBL_VOLUME_DIR`) | after check 2: `index=cribl sourcetype=cribl:audit earliest=-1h` | entries for `users` / `lookups` | `docker exec cribl sh -c 'ls $CRIBL_HOME/log $CRIBL_VOLUME_DIR/log'`; point `in_cribl_audit.path` at the folder that holds `audit.log` |
| 8 | `cribl_metrics` delivery | the play waits for `mstats` > 0 | yes | metadata `index` on `CriblMetrics` not honoured: add an Eval `index='cribl_metrics'` in a `pl_cribl_self` pipeline on `r_cribl_self`, filtered to metrics |
| 9 | UDM `_time` = receive time | the self-test asserts skew ≤ 60 s for a line stamped `Jan  1 00:00:00` | yes | `pipeline:` (pre-processing) not taken on syslog sources: move the Eval into a `pl_syslog` route pipeline that chains to `pl_test_block`, or fold it into `pl_test_block` behind `__inputId.startsWith('syslog:')` |
| 10 | UDM source field | the self-test filters on `source="syslog:udm"` | found | if Splunk shows `source=tcp:9997`, Cribl's metadata `source` isn't forwarded: set it with an Eval in `pl_syslog_pre` |
| 11 | **Idempotence** | the second run | `changed=0` | the markers and the read-only checks are `changed_when: false`; anything else that changes is a bug |
| 12 | **Test block** | `--tags cribl_block -e "hl_block_key='udm|*|*'" -e hl_block_minutes=5 -e "hl_block_reason='3b check'"`, wait 20 s, then send a line: `$u=New-Object Net.Sockets.UdpClient; $b=[Text.Encoding]::ASCII.GetBytes('<13>Nov  1 00:00:00 x hl: HL_BLOCKTEST'); $u.Send($b,$b.Length,'127.0.0.1',5514)` | not in Splunk; Cribl's `hl_ingest_block.csv` and Splunk's mirror `\| inputlookup hl_ingest_block` both show the row | `docker exec cribl sh -c 'find / -name hl_ingest_block.csv 2>/dev/null'` and check the lookup id the pipeline names |
| 13 | Clear the block | `--tags cribl_block -e "hl_block_key='udm|*|*'" -e hl_block_clear=true`, send again | arrives | — |
| 14 | **Remove + reinstall** | `--tags cribl_remove`, then `--tags cribl` | contract passes; `docker ps -a`, `docker volume ls` clean; wd2l HEC healthy; reinstall sets the password again | — |
| 15 | wd2l unaffected | `soak-check.sh` on wd2l-recv | green | — |

**Restart budget:** check 6 adds 1–3 splunkd restarts. Cribl restarts are free (UFs ACK).

## Then

- Spec: add **§14.9 Task 3b checks** (one row per check above, with what you saw). Update §5.3's `cribl`
  row (config as files plus the manifest, the API for the password and lookup, the self-test), add a
  `cribl_block` row, and §7.2/§7.8: the mirror answers the open item; task 11b wires it in.
- `docs/data-health/*.md`: no macro or panel changed in 3b, so no update.
- PR: title `feat(cribl): Cribl Stream deployment, config as code and the test block (task 3b)`,
  body `Closes #24` plus the check table. Merge when `lint` and `pr-issue-link` are green.
- Then rebase `feat/4-uf-linux` onto `main` (it is stacked on this branch).
