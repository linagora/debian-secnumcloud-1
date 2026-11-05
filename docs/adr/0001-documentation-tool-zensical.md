# ADR-0001: Documentation tool: Zensical

- **Status**: Proposed
- **Date**: 2026-11-05
- **Deciders**: TBD
- **Related issue**: #1

## Context

The project needs a documentation site generated from Markdown files in the repository (`docs/`) and built by CI. The tool must be easy for every team member to use and produce a static site.

## Considered options

### Option 1: Zensical

- Pros: successor to Material for MkDocs, by the same team; simple configuration (`zensical.toml`); fast builds; already used by [apparmor.d](https://github.com/roddhjav/apparmor.d), a project close to ours; `--strict` mode makes CI fail on warnings ; suggested by Linagora team.
- Cons: young tool (0.x), plugin ecosystem still limited.

### Option 2: MkDocs + Material for MkDocs

- Pros: very mature, large plugin ecosystem.
- Cons: Material for MkDocs is in maintenance mode; its authors recommend migrating to Zensical.


## Decision

Zensical, as proposed in issue #1. The version is pinned in `requirements-docs.txt` for reproducible builds.

## Consequences

- Configuration lives in `zensical.toml` at the repository root; content lives in `docs/`.
- Every new page must be referenced in `nav`.
- Zensical upgrades are explicit, through a PR that changes `requirements-docs.txt`.
