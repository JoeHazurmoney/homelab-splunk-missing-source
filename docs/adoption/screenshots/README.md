# Screenshots for the adoption package

These pictures come from the live lab. They were taken on 2026-11-15 and 2026-11-16 (UTC) for the
[pitch deck](../deck/README.md) and the training material. Each one shows a real state of the app.
Some states were staged on purpose, as the table says.

## What each picture shows

| File | Shows | Scenario |
|---|---|---|
| `01-overview-top.png` | The Overview banner and KPI tiles, with one sourcetype missing | S2 |
| `02-needs-attention-test-block.png` | A Needs attention row: `cpu` MISSING, with its cause and action | S2 |
| `03-unregistered.png` | Manage: data seen but not on the expected list | S0 |
| `04-thresholds.png` | Manage: each item's limit and where it comes from | S0 |
| `05-needs-attention-cribl-down.png` | Needs attention with Cribl stopped: "Cribl DOWN" causes | S5 |
| `06-restarts.png` | Restarts and agent stops: explained and not explained stops | S0 (S3, S4) |
| `07-tamper.png` | Tamper findings of the last 24 h | S0 (S4) |
| `08-host-detail-items.png` | Host detail: each item of wd2l-logsrv against its limit | S2 |
| `09-mute-preview.png` | Manage: the preview of a host mute | S1 |
| `10-mute-result.png` | Manage: the result after Apply | S1 |
| `11-admin-log.png` | Manage: the admin log | S1 |
| `12-soh-top.png` | Daily state of health: the KPI row and outages | S0 |
| `13-hosts-muted.png` | The Hosts muted tile at 1 | S1 |
| `14-test-block-command.png` | Manage: the command that sets a test block | S2 |
| `15-recovered.png` | Recently recovered items | S5 |

## The scenarios

The lab owner approved each staged step before it ran.

| Step | What was done | Undone by |
|---|---|---|
| S0 | Nothing. The lab was healthy. | — |
| S1 | Muted wd2l-logsrv (whole host) for 1 h on Manage. | Unmuted on Manage. |
| S2 | A 15-min test block on wd2l-logsrv's `cpu`, with the role's `cribl_block` tag. | It ended by itself. |
| S3, S4 | No new action. The panels already held an Ansible restart and two stops nobody explained. Those were left by the #52 live proofs. | — |
| S5 | `docker stop cribl`. Taken once `cribl` was DOWN. | `docker start cribl`. |

## How to take them again

Two tools in `tools/capture/` do it:

- `capture_screens.py` runs in its own container. It logs in to Splunk Web and saves each panel as a
  PNG, plus a full view. It does this for each dashboard and for each tab of Manage. It can fill in
  a Manage form from the URL and choose Apply. That is how S1 was done.
- `crop.py` turns the raw captures into the named files above.

Build the image once. On HOMEPC, in Git Bash, in `tools/capture`:

```bash
docker build -t hl-capture:1.52.0 .
```

Then take one scenario. On HOMEPC, in Git Bash, any folder:

```bash
MSYS_NO_PATHCONV=1 docker run --rm --network hl-net \
  -v "C:/Users/taylo/wd2l-splunk/secrets/splunk-admin-password:/secrets/pw:ro" \
  -v "C:/path/to/captures:/out" \
  hl-capture:1.52.0 --set s0 --pages overview host:wd2l-recv manage soh
```

- The container joins `hl-net`, so it reaches Splunk at `wd2l-splunk:8000`.
- The password file is mounted read-only. It is never written anywhere.
- `--wait` sets how long each page gets for its searches. The default is 35 s.
- With `--query` and `--apply`, it fills in a Manage form and writes the change. Only use them for
  a change you mean to make.
