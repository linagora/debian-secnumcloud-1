# ADR-0002: Documentation hosting: GitHub Pages

- **Status**: Proposed
- **Date**: 2026-11-05
- **Deciders**: TBD
- **Related issue**: #1

## Context

The documentation site must be published automatically on every merge to `main` and be reachable from the README. The repository is public and hosted on GitHub.

## Considered options

### Option 1: GitHub Pages (deployed via GitHub Actions)

- Pros: integrated with the repository, free for a public repository, no infrastructure to maintain, native CI deployment (`actions/deploy-pages`), no secrets to manage.
- Cons: hosted outside France / outside the SecNumCloud scope; dependency on GitHub.

### Option 2: Linagora internal hosting

- Pros: full control over hosting, consistent with a sovereignty approach.
- Cons: infrastructure and deployment secrets to manage, longer setup time.

## Decision

GitHub Pages, deployed by the `.github/workflows/docs.yml` workflow. The documentation is public and contains no sensitive data; since the site is static, migrating to another host later remains easy.

## Consequences

- The site is available at <https://linagora.github.io/debian-secnumcloud-1/>.
- In the repository settings, *Settings → Pages → Source* must be set to **GitHub Actions**.
- No sensitive information (keys, internal addresses, etc.) may be published in `docs/`.
