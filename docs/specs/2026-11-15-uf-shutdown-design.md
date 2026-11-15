# Design: a tamper finding when the Splunk agent stops, and a panel of restarts (#52)

Status: draft for Taylor's approval, 2026-11-15. Issue #52. Base: `main` at `433b3bd`. A builder check (a fresh reviewer) read it; its six questions are answered in place, marked "Builder check Qn".

## 1. Why

Someone who wants to hide activity on a host can stop the Splunk agent (the UF), do the work, and start the agent again. If that takes a few minutes, the host never reaches DOWN, so nothing on the dashboards says it happened. The app's tamper indicators are meant to catch this:
- **Linux** already does. auditd's `SERVICE_STOP` for the `SplunkForwarder` unit gives `svcstop_splunkforwarder`.
- **Windows Server** does through `win7036` (Service Control Manager event 7036, "service stopped").
- **Desktop Windows (8 and later, Home and Pro) doesn't.** Microsoft stopped logging 7036 there. HOMEPC is Windows 11 Pro and has no 7036 at all, so a stop-and-start on HOMEPC leaves no finding.

Taylor's decisions (2026-11-15):
- Detect an agent stop from the agent's own shutdown line in `_internal`, on Windows and Linux (#52 option b).
- A stop during a whole-host shutdown or reboot is **explained, not alerted** (option a).
- That is acceptable only with a **panel that shows restarts and agent stops**, so explained stops stay visible. It goes on the Overview (24 h) and Host detail (7 d).
- `win7036` stays (Windows Server logs it).

## 2. Goals, non-goals, anti-goals

**Goals**
1. An agent stop that no planned work explains raises one tamper finding and one *DH Alert tamper*, on Windows and Linux.
2. An agent stop during role work (an Ansible marker) or a host shutdown is stored as explained, with the reason, and doesn't alert.
3. One stop gives one finding, even when several indicators see it (the shutdown line, `svcstop_splunkforwarder`, `win7036`).
4. Every stop, explained or not, shows in a *Restarts and agent stops* panel on the Overview (24 h) and Host detail (7 d), with what explained it.
5. VM shutdowns stop raising tamper alerts from the stop codes Linux already has (`svcstop_*`, `audit_daemon_end`). They show in the same panel instead.

**Non-goals**
- Crashes and power loss. They write no shutdown line. The host still goes LATE, then DOWN, and the Hyper-V panel shows a VM reset. Windows 41/6008 ("unexpected shutdown") could be added later.
- A stop that stays down. DOWN already covers it.
- Changing what a marker explains, or the 15 min / 60 s marker window.

**Anti-goals** (it fails even if it works technically when...)
- A planned VM or PC shutdown sends a tamper alert.
- A stop vanishes from every screen because it was explained.
- An unexplained stop is hidden because evidence for it arrived late.
- One stop sends two alerts.

## 3. What exists today (facts the design builds on)

- **DH Tamper** (`savedsearches.conf`) runs every 5 minutes. It reads events by **index time** (`_index_earliest=-15m`, `earliest=-7d`), so a line that arrives late is still read. Each indicator macro gives `host time code indicator detail`. `dh_tamper_finish` makes one finding per host, code and 5-minute bucket, then decides suppression **once, when the finding is first stored, and never changes it after that** (#49). Suppressed means a marker for the host came up to 900 s before the finding or 60 s after it. `dh_tamper_fold` already merges a 7045 and a 4697 for the same service into one finding (#50); that is the pattern for goal 3.
- **The agent's shutdown line.** `index=_internal sourcetype=splunkd component=Shutdown "Shutting down splunkd"`, for example `11-14-2026 18:37:19.550 -0700 INFO  Shutdown [15544 Shutdown] - Shutting down splunkd` (homepc) and `11-11-2026 04:49:27.820 +0000 INFO  Shutdown [923181 Shutdown] - Shutting down splunkd` (wd2l-recv). In the last 30 days: homepc 13, pi5 6, wd2l-logsrv 9, wd2l-recv 33. The indexer container `wd2l-splunk` (22) and the old `hlspike-uf` (1) write it too; only UF hosts count.
  - About two thirds of the lines arrive only after the agent **starts again**: it writes the line, then exits before forwarding it. The lag from `_time` to `_indextime` reached 841 s (p90 3–5 min).
- **What those 61 lines were:**

  | Cause | Lines |
  |---|---|
  | Role work (a marker 900 s before or 60 s after) | 52 |
  | A whole-host shutdown or reboot, no marker | 7 (homepc 2, wd2l-logsrv 3, wd2l-recv 2) |
  | Neither: the case this is for | 2 (pi5 1, wd2l-recv 1) |

- **Host-shutdown evidence that reaches Splunk:**
  - Windows, `index=windows sourcetype=XmlWinEventLog`, `XmlWinEventLog:System`: **1074** from `User32` (a shutdown or restart was started, with the user, the process and the reason; 8 in 30 days), **6006** from `EventLog` (the event log service stopped cleanly; 7), **6005** (it started; 8). 41 (`Kernel-Power`) and 6008 (`EventLog`) mark an unexpected shutdown (1 each).
  - Linux, `index=linux sourcetype=linux_audit`: **`type=SYSTEM_SHUTDOWN`** (3 on wd2l-logsrv). A shutdown also stops many units at once (`SERVICE_STOP` of sshd, systemd-logind, dracut-shutdown, ...) and ends auditd (`DAEMON_END`). A boot logs `SYSTEM_RUNLEVEL old-level=N new-level=3`.
  - **These records are often written after the agent stopped**, so they reach Splunk only when the host boots again: minutes later for a reboot, hours later for a VM shut down overnight. Meanwhile the agent's own line sometimes arrives at once. **So an agent stop can't be judged when its first line arrives.** This is the main design problem.
- **Today's stop findings** (`dh_tamper`, 30 days): `svcstop_splunkforwarder` 30 (24 suppressed); on wd2l-logsrv `audit_daemon_end` 3, `svcstop_rsyslog` 3 and `svcstop_splunkforwarder` 3 unsuppressed. These are VM shutdowns that alerted.
- **The evaluator** (`dh_eval_cause`) uses unsuppressed findings near a silence to give the cause "Possible deliberate blinding: …".
- **Panels.** The Overview has *Tamper findings (first seen in the last 24 h)*, unexplained only. Host detail has *Tamper findings on this host* (unexplained only) and *Hyper-V VM events (7 d)* (VMs only). Nothing shows a restart for HOMEPC or pi5, and nothing shows an explained stop.

## 4. Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | A new indicator from the agent's shutdown line, plus host-shutdown evidence, a hold before judging, a fold with the other stop codes, and the panel. | Uses lines every OS already sends; no new input. Alerts come a few minutes after the agent is back, not at the stop. |
| B | Infer a stop from a gap in the agent's own heartbeat (`_internal` metrics). | Also catches crashes and `kill -9`. But it can't tell a stop from a network pause, a Splunk restart or PC sleep, so it's noisy. |
| C | A new Windows input that polls the service state. | Needs a new input on every Windows host, and stops with the agent it watches. |

Taylor chose the shutdown line (A) in #52. B and C don't fit: B can't tell a stop from a pause, which is the noise the app works hardest to avoid; C adds an input that dies with the agent.

## 5. Design

### 5.1 The new indicator
- A new macro (in the style of `dh_tamper_linux`) reads the shutdown line. Code `uf_shutdown`; indicator "Splunk agent stopped (shutdown line)"; detail with the log source. `host` is normalized with `dh_host_norm`; `time` is the line's `_time` (when the stop happened). Selection stays by index time, like every DH Tamper source.
- Only **UF hosts** count. A host counts when the app knows it has a Splunk agent (`dh_fwd`, the arrival tracker's forwarder facts) or its expected rows say `collection=uf`; the builder picks which. `wd2l-splunk` and `cribl` never count.
- DH Tamper's search adds an `_internal` branch. It must stay cheap: `component=Shutdown` plus the phrase, the existing `_index_earliest=-15m` window.

### 5.2 One stop, one finding (fold)
These codes describe the same event, an **agent stop**, when they are on the same host within `dh_tamper_window_secs` (900 s):
- `uf_shutdown`
- `svcstop_splunkforwarder` (Linux `SERVICE_STOP`)
- `win7036` for the SplunkForwarder service

They fold into one finding, the way `dh_tamper_fold` folds 7045+4697: the earliest event gives the finding id; a stored finding keeps its id; a half that has already alerted is never followed by a second alert. The indicator names every source seen, for example "Splunk agent stopped (SERVICE_STOP + shutdown line)". `win7036` for other services (eventlog) is not folded.

### 5.3 Judge a stop only when its evidence can have arrived (hold)
**Which findings are held.** The hold applies only when **the agent itself stopped**:
- the agent-stop finding from 5.2; and
- a finding of `svcstop_auditd`, `svcstop_rsyslog`, `audit_daemon_end`, `audit_daemon_abort` or `win1100` **when** an agent-stop finding exists for the same host within 900 s of it. These are the codes a host shutdown also produces.

The same codes on a host whose agent kept running (auditd stopped, the agent still sending) are real log tampering. They are judged at first store, exactly as today, with no added delay. So are all other codes. *(Builder check Q3; controller's call.)*

**How a held finding is judged.**
- **Explained, at once,** when:
  - a marker matches, by today's rule (900 s before, 60 s after) → reason `role work`; or
  - host-shutdown evidence for the same host is **from 600 s before the stop to 120 s after it** (5.4) → reason `host shutdown`. Measured on 11-08/09: Windows 1074 came 21 s before the agent's stop line and 6006 in the same second; Linux `SYSTEM_SHUTDOWN` came 2–12 s after it. The window is lopsided on purpose: an attacker who stops the agent, works, and then reboots to cover it is explained only if the reboot is within 2 minutes. *(Builder check Q4; controller's call.)*
- **Otherwise it stays pending** until the host's agent has been heard from again after the stop, plus a settle time for the backlog. The builder picks the "heard from" source (the arrival tracker's last heartbeat, or any `_internal` event) and the settle time (about 10 min). Then check once more. If nothing explains it, it is judged **unexplained** and it alerts.
- **If the agent never comes back, the finding stays pending and never alerts.** A host that stays down is DOWN, which alerts on its own (#52: the shutdown line is reliable for a stop and then a start, not for one that stays down). This keeps a VM shut down for days from alerting at some cutoff. The panel shows it as "Waiting for the host to report back". It ages out with the 30-day `dh_tamper` retention. *(Builder check Q1; controller's call, from Taylor's anti-goal "a planned VM or PC shutdown sends a tamper alert". There is no cap, so no re-judging is needed.)*
- Once judged, a finding never changes (#49 still holds; it now applies at judging time, not at first store).
- A pending finding doesn't alert, and **the evaluator ignores it** for the cause. Otherwise a VM shut down overnight would read "Possible deliberate blinding" all night. A stop that is still pending when a row goes silent gives no tamper cause yet. The host's own cause (DOWN, agent stopped) still shows.

### 5.4 Host-shutdown evidence
- **Windows:** System events 1074 (`User32`) and 6006 (`EventLog`). The 1074 gives the user and the reason, and those go in the finding's explanation, for example "host shutdown: restart by HOMEPC\taylo (Operating System: Upgrade (Planned))".
- **Linux:** `linux_audit` `type=SYSTEM_SHUTDOWN`. All 3 real shutdowns in the data have it. The plan starts with a read-only check of more live shutdowns (the live-proof reboot in 6 gives one more). The fallback is in scope only if a shutdown is found without `SYSTEM_SHUTDOWN`. It would be evidence-only rows (never findings) from a `SERVICE_STOP` of `systemd-logind` or `dracut-shutdown`, which needs a new search term, since `dh_tamper_linux` reads only SplunkForwarder/auditd/rsyslog stops today. *(Builder check Q6; controller's call.)*
- The evidence is read in the same DH Tamper run, by index time, like markers (`dh_kind="hostdown"`). It is matched against the pending findings stored in `dh_tamper` as well as new ones, because on Linux it often arrives only when the host boots. The search range stays 7 days by `_time`, so a host that was off for longer than that stays pending.

### 5.5 What a finding records
`dh_tamper` gets new fields:
- `state`: `pending` or `judged`.
- `explained_by`: `role work`, `host shutdown` or empty.
- `explanation`: one line, for example "Ansible run restart by taylorb (run 3f2a…)" or "host shutdown: restart by HOMEPC\taylo (…)".

`suppressed` keeps its meaning: 1 = explained. Existing rows read as judged. *DH Alert tamper* stays "new, unsuppressed findings", collected only once judged. `dh:tamper` events carry the same fields.

### 5.6 The panel: *Restarts and agent stops*
- **Overview, 24 h:** one row per **stop episode**, newest first. An episode is all the held findings of one host within 900 s of each other. A Linux VM shutdown gives up to four (`svcstop_auditd`, `svcstop_rsyslog`, `audit_daemon_end`, the agent stop), and they show as one row whose **What** lists them. Every host shutdown stops the agent, so every one has an agent-stop finding and shows; a crash doesn't (a non-goal). *(Builder check Q5; controller's call. The builder picks how to group: at display time, or with a stored episode key.)*
  - Columns: **Time**, **Host**, **What** (Splunk agent stopped / auditd stopped / host shut down or restarted / ...), **Explained by** (Ansible run … / Host shutdown: … / **Not explained** / **Waiting for the host to report back**).
  - "Not explained" is styled as a warning. Click a row for Host detail.
  - It reads the app's stored findings (`dh_tamper` / `dh:tamper`), not raw events, so it is cheap. Filters follow the Overview's (site, owner, criticality).
- **Host detail, 7 d:** the same panel for one host, beside *Hyper-V VM events*.
- Help text and a `docs/data-health/dashboards.md` entry for each, so `dash_check` docs-coverage passes. The *Tamper findings* panels keep showing unexplained findings only.

### 5.7 Docs
- `data-health-design.md`: the tamper indicators table (new code, the fold, the hold, host-shutdown explanation), and what desktop Windows now has.
- `runbook-missing-data.md`: what to do for "Splunk agent stopped (not explained)", and how to read the new panel.
- `dashboards.md`: the two panel entries. `glossary.md`: "explained", "pending". Same plain-language style as the docs pass.

## 6. Constraints

- **App only.** No role change is expected; DH Tamper already runs as a scheduled search that can read `_internal`. If the builder finds otherwise, say so before changing the role.
- **Fixtures first** (`tests/spl/run.sh`, real raws for both OSes), covering:
  - an unexplained stop-and-start (one finding, alerts once, after the hold);
  - role work (explained at once);
  - a Linux VM shutdown with `SYSTEM_SHUTDOWN` arriving after the stop line (pending, then host shutdown, no alert);
  - a Windows restart with 1074 (host shutdown, with the user);
  - the fold (shutdown line + `svcstop_splunkforwarder`: one finding);
  - a stop that never comes back (stays pending, no alert);
  - an auditd stop with the agent still running (judged at once, alerts, as today);
  - a stop, then a reboot more than 120 s later (not explained);
  - the evaluator ignoring pending findings;
  - the existing tamper cases (22, 57, 57b, 58, 59, 61, 77, 79, 79b, 85). Their stop codes come without an agent stop, so they keep today's expectations. Any case that pairs one with an agent stop is updated to the new rule, and the plan names each such change. *(Builder check Q2.)*
- **Live proofs**, against the lab:
  - Linux role work (a `restart` run → explained).
  - A Linux unexplained stop-and-start on one VM (`systemctl stop` then `start` without a marker, via Ansible from pi5 → one alert).
  - A Linux VM reboot (→ host shutdown, no alert).
  - Windows needs **Taylor's OK** before stopping the service on HOMEPC. Its proofs are a role restart, an unexplained stop-and-start, and (when Taylor next restarts the PC) a host restart.
- **Performance:** DH Tamper stays a 5-minute search; the new branches use index time and narrow terms.
- **Compatibility:** stored findings without `state` read as judged. No KV migration that rewrites old rows.
- **Writing rules:** plain-language docs (the docs-pass style guide); "customer", never government wording; no secrets.

## 7. Left to the builder

- Which source says "this host has a UF" (`dh_fwd` or the expected rows) and which says "heard from again".
- The settle time (about 10 min), as a macro with a comment.
- The exact indicator and explanation wording, within the style guide.
- Whether the Linux `SERVICE_STOP`-burst fallback is needed (5.4).
- The panel's layout size and position on each view, within the Studio layout's existing grid.
- How the fold generalizes `dh_tamper_fold` (one mechanism for 7045+4697 and the agent stop, or a second one).
