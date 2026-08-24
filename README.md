# cash_discount

Personal dbt project for cash discount analytics and modeling.

## Setup

1. Configure your warehouse connection in `~/.dbt/profiles.yml` (profile name: `cash_discount`).
2. From this folder:

```bash
dbt debug
dbt run
dbt test
```

## Project docs

- `docs/decisions.md` — architecture and modeling decisions
- `.cursor/rules/` — Cursor AI conventions for this workspace
