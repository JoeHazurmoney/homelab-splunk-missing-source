# The pitch deck

The pitch deck makes the case for running `hl_data_health` in production. It is written for a
customer's SOC and security leads. It covers Splunk Enterprise only.

- **The deck itself** is a Slides artifact on claude.ai:
  <https://claude.ai/artifact/1rL9tHSg9gqCb3AyxnGwr2>. It is private until its owner shares it.
  From there it downloads as PowerPoint (.pptx) or PDF.
- **This folder** keeps its source, so changes can be reviewed. `project/deck.json` lists the
  slides in order. `project/deck.css` holds the shared look. `project/slides/` has one HTML file per
  slide. Each slide's speaker notes are in its `<aside>`.
- **The pictures** are in [the screenshots folder](../screenshots/README.md). The slides load them
  from the artifact's own store (`/_blob/…`), so they show only in the artifact.

## The story

| Part | Slides |
|---|---|
| The problem | A silent source is a blind spot nobody sees. |
| What it does | The Overview, and one finding read aloud: what, why and what to do next. |
| How it works | Expectations from the inventory; a limit per item; the cause chain; tamper findings; Host detail; Manage. |
| Why trust it | The test results; a fair look at the alternatives; the roadmap; the ask: a pilot on one site. |
| Backup | Architecture, timings, test results, prerequisites, lab to production, and how it was built. |

## Keeping it true

Every number on a slide comes from the repo. Check a change against these sources:

- [data-health-design.md](../../data-health-design.md): timings, profiles and alerts.
- [The fault-injection record](../../records/2026-11-fault-injection-run.md): test results.
- [The roadmap](../roadmap.md) and [the prerequisites](../prerequisites.md).

Two facts come from outside the repo. They were checked on 2026-11-15:

- Splunk's Monitoring Console judges forwarders by the connections the indexers see.
- TrackMe's Splunkbase page says its free Community Edition was discontinued.
