# Training material for the HL Data Health app

This folder holds the training for the customer's SOC analysts and Splunk admins. It is feature
[F7 Training](../roadmap.md#f7-training) of the adoption roadmap. Each piece teaches one job, in plain
words, with real screenshots.

This folder has two jobs. It lists every planned piece. And it sets the **template and the
conventions** that every piece follows. The pieces marked "Example" were written first, to show the
style. Write the rest the same way.

## Every planned piece

| Piece | For | Status |
|---|---|---|
| Analyst guide: your first five minutes with a finding | Analyst | Example: [first five minutes](example-analyst-first-five-minutes.md) |
| Analyst guide: read the banner and the tiles | Analyst | To write (F7) |
| Analyst guide: Needs attention, cause and action | Analyst | To write (F7) |
| Analyst guide: Host detail | Analyst | To write (F7) |
| Analyst guide: the tamper and restarts panels | Analyst | To write (F7) |
| Analyst guide: the Daily state of health page | Analyst | To write (F7) |
| Admin guide: Manage basics and the admin log | Splunk admin | To write (F7) |
| Admin guide: mute a host or an item | Splunk admin | To write (F7) |
| Admin guide: limits and criticality | Splunk admin | To write (F7) |
| Admin guide: add, adopt and retire rows | Splunk admin | To write (F7) |
| Admin guide: test blocks | Splunk admin | To write (F7) |
| Runbook: on hold (tracker or Splunk) | Analyst | To write (F7) |
| Runbook: muted, new or test block | Analyst | To write (F7) |
| Runbook: planned work (the automation stopped or removed the agent) | Analyst | To write (F7) |
| Runbook: the VM is off | Analyst | To write (F7) |
| Runbook: possible deliberate blinding | Analyst | To write (F7) |
| Runbook: Cribl or relay down | Analyst | To write (F7) |
| Runbook: device problems | Analyst | To write (F7) |
| Runbook: the Splunk agent is late or stopped | Analyst | To write (F7) |
| Runbook: the agent works but an input is missing | Analyst | To write (F7) |
| Runbook: one stream stopped | Analyst | To write (F7) |
| Runbook: never arrived | Analyst | To write (F7) |
| Runbook: Splunk agent stopped (not explained) | Analyst | Example: [agent stopped](example-runbook-agent-stopped-not-explained.md) |
| Analyst deck (30 minutes) | SOC lead | Example module: [first five minutes](deck/README.md). The rest is to write (F7). |
| Admin deck | SOC lead | To write (F7) |
| Hands-on exercises with test blocks | Analyst, admin | To write (F7) |
| Quiz or sign-off per person | SOC lead | To write (F7) |

The runbook pieces follow the causes in [the lab runbook](../../runbook-missing-data.md). The
customer's copy needs its own commands and contacts.

## Conventions

Every piece follows these rules.

**Reading level.**
- Aim for grade 8 or lower, with about 15 words a sentence on average.
- Use short, plain words. Explain a term the first time. Link to the [glossary](../../glossary.md).
- Check it with `tools/doc_grade.py`. It runs in a container:
  `docker run --rm -v "${PWD}:/w:ro" -w /w python:3.14.10-slim python tools/doc_grade.py --worst 3`.

**Voice.**
- Talk to the reader: "you". Use the active voice.
- Name roles, never people: "the Splunk admin", "the on-call analyst", "the platform owner".
- Say "customer". Do not name any person.
- Write for production. Cover Splunk Enterprise only.

**The "In the lab:" rule.**
- The lab runs its steps as Ansible role tags on a Raspberry Pi called pi5. The customer will not
  have those tags.
- So first say what the step must do. Then show the lab's command, labelled "In the lab:". The
  customer maps it to their own automation.

**Screenshots.**
- Use the pictures in [`../screenshots/`](../screenshots/README.md). Link them with a relative path,
  for example `![The Overview banner and tiles](../screenshots/01-overview-top.png)`.
- Write alt text that says what the picture shows. Open the picture and check it first.
- Say in the text what the reader should look at. Do not rely on the picture alone.
- To take a picture again, follow the README of that folder. It uses the tools in `tools/capture/`.

**Link, do not copy.**
- For what a panel shows, link to [the dashboard guide](../../data-health/dashboards.md). Do not
  repeat its text.
- Say only what the reader needs for this job.

**Check yourself.**
- End each guide section with a "Check yourself" heading.
- Give 4 or 5 questions. Put the answers in a collapsed `<details>` block.

## The runbook template

Copy this for each finding. Use these headings, in this order. Fill each one in. If a heading does
not apply, write "Not applicable" and say why.

````markdown
# Runbook: <finding name>

<One or two lines: what this finding is, and who reads this page.>

## What you see
The exact Cause text, as the Overview shows it. Mark the parts the app fills in with <...>.
Add a screenshot of the row or panel.

## What it means
Two or three short sentences. What the app saw, and what it did not see.

## How urgent
- Does an alert fire? Which one, and how often?
- What does criticality change?
- How fast should the analyst act?

## First five minutes
1. A numbered step. One action each.
2. Name the panel, the search or the command.
3. End with a clear decision: fix it, wait, or escalate.

## Fix
What puts it right. For each step, say what it must do. Then show "In the lab:" with the lab's
command.

## Escalate when
- The condition that needs another person.
- Who that person is. Use a role, and the customer fills in the contact.

## Evidence to save
- What to copy before you change anything: searches, screenshots, times.

## Related
- Links to the dashboard guide, the glossary and the nearby runbooks.
````
