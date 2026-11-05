# Architecture Decision Records (ADR)

ADRs record the project's significant architecture decisions, along with their context and consequences.

## Writing an ADR

1. Copy the [template](template.md) to `docs/adr/NNNN-short-title.md`, where `NNNN` is the next number (4 digits).
2. Fill in every section. The initial status is **Proposed**.
3. Add the page to the `ADR` section of `nav` in `zensical.toml`, and to the list below.
4. Open a pull request; the status becomes **Accepted** once the PR is merged after review.

An ADR is never deleted: if it is replaced, its status becomes **Superseded by ADR-NNNN**.

## ADR list

| No. | Title | Status |
|---|---|---|
| [0001](0001-documentation-tool-zensical.md) | Documentation tool: Zensical | Proposed |
| [0002](0002-hosting-github-pages.md) | Documentation hosting: GitHub Pages | Proposed |
