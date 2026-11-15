Closes #<issue number>

<!--
Title: a conventional commit, for example `docs: rewrite the runbook in plain language`.
Types: feat, fix, docs, test, refactor, chore, ci, build, perf, style, revert.
The `pr-issue-link` check fails without `Closes #<n>` for an open issue, or without this title form.
-->

## Summary

What changed, and why. Two or three sentences.

## Checks

Tick each one that applies. Write "n/a" next to the ones that don't.

- [ ] Lint passes: `yamllint --strict .` (and `ansible-lint --strict` for role changes).
- [ ] Docs checks pass: `python tests/spl/dash_check.py docs splunk/apps/hl_data_health docs/data-health` (for changes under `docs/data-health/` or the views).
- [ ] Links and anchors resolve in every changed Markdown file.
- [ ] Grade check passes: `python tools/doc_grade.py --check` (run it in a Python container, not on the host).
- [ ] `tests/spl/run.sh` passes (for changes to the app, macros, views or fixtures; needs Splunk).
