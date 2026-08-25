# Providentia homeowner client contributor contract

## Repository boundary

This repository owns the multi-platform Flutter application used by household
members. The backend lives in `providentia-systems/backend`; the separate Linux
Flutter operator application lives in `providentia-systems/admin`. Do not add
platform administration, moderation, account management, or billing-operator
surfaces to this homeowner application.

## Start every development session

On a Debian or Ubuntu contributor host, run:

```bash
bash tools/agent-setup.sh
source .agent-env
```

Read `tools/agent-requirements.json`, `docs/agent-development.md`, and
`docs/architecture.md` before changing toolchains, workflows, or application
boundaries. The canonical setup runs generation, structure, formatting,
analysis, tests, coverage, and the Linux release build. Do not describe an
unrun check as passing and do not weaken a gate because a runner is restricted.

## Architecture and privacy

- Preserve Domain/Application/Infrastructure/Presentation boundaries and use
  constructor-injected ports rather than service locators.
- Fail closed on active-home and household-permission mismatches.
- Keep AI credentials write-only and home-scoped. Images remain ephemeral,
  sanitized, explicitly consented, and review-only until an ordinary inventory
  or purchasing command is separately confirmed.
- Private products and categories must work without contribution consent.
  Contribution is explicit, field-scoped, and revocable.
- Never log media, credentials, household prices, private notes, or filesystem
  paths. Never add real household images as fixtures.

## Contract and completion

`contracts/providentia-v1.json` and its lock are frozen backend contract inputs.
Generated bindings, adapters, tests, and backend changes move together. Keep
changes focused and human-readable. Before handoff run the canonical setup,
review `git diff --check`, and ensure required GitHub checks are green.
