# Thunderbird for Android reports

This repository publishes automatically generated reports for the [Thunderbird for Android](https://github.com/thunderbird/thunderbird-android) project.

## Find a report

- [Browse monthly merged pull request reports](reports/merged-prs/README.md) — the report index, with Markdown and CSV downloads for every month.
- [Browse CSV exports](reports/merged-prs/csv/) — spreadsheet-friendly data for all available months.

Reports are updated daily. Each run refreshes the current month and the three preceding months so that release and beta information remains current.

## What's in a report?

Each monthly report lists pull requests merged into the `main`, `beta`, and `release` branches. It includes the merge date, author, merge commit, feature-flag reference, report status, and the first beta or release tag that contains the change.

The Markdown report groups entries by status:

- **Highlight**, **Include**, and **Review** are shown as regular sections.
- **Exclude** remains available in a collapsed section for auditability.

Short merge SHAs and beta or release tags link to their corresponding GitHub pages.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for report generation and automation details.
