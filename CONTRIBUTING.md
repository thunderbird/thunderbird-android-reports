# Contributing

This repository contains generated project reports and the tooling used to update them.

## Contents

- `scripts/generate-merged-pr-report.sh` - merged pull request report generator
- `merged-prs/` - committed Markdown reports and an auto-generated report index
- `merged-prs/csv/` - committed CSV exports for spreadsheet or tool usage
- `.github/workflows/update-merged-pr-reports.yml` - GitHub Actions workflow that generates and commits report changes

## Requirements

Local generation requires:

- `git`
- `gh`, authenticated with access to the source repository
- `jq`
- macOS/BSD `date` or GNU `date`

## Generate Locally

Generate a report for a specific month:

```bash
./scripts/generate-merged-pr-report.sh 2026 02 merged-prs
```

The generator defaults to `thunderbird/thunderbird-android`. Override the source repository with environment variables:

```bash
REPORT_OWNER=thunderbird REPORT_REPO=thunderbird-android ./scripts/generate-merged-pr-report.sh 2026 02 merged-prs
```

## GitHub Workflow

The workflow can be run manually with a year, month, and lookback month count. If no year and month are provided, the workflow ends at the previous calendar month. The lookback defaults to 3 months.

The scheduled workflow runs daily at 06:15 UTC and regenerates the configured lookback window so release/tag updates can update older monthly reports.

The workflow commits changed files under `merged-prs/` back to the report repository. Markdown reports and the report index are written to `merged-prs/`; CSV exports are written to `merged-prs/csv/`. Each Markdown report links to its matching CSV export. It uses `GITHUB_TOKEN` for public repository access and repository write access.
