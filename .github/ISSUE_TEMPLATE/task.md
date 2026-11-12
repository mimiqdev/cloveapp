---
name: Task
about: One development-plan task, written as a worker's brief
title: "[<ID>] <task name>"
labels: task
---

<!-- See docs/AGENT-WORKFLOW.md. This issue is the worker's complete brief. -->

## Goal

<!-- One or two sentences: what exists when this is done. -->

## Read first

- `AGENTS.md`
- `docs/DEV-PLAN.md`, row <ID>
- `docs/PRD.en.md`, <P0 items>
- <other files, spike reports, or decisions>

## Scope

In scope:

-

Out of scope:

-

## Acceptance criteria

- [ ]

## Checks to run

<!-- Exact commands. The worker pastes their output into the pull request.
     mise run check on every change (no simulator); CI runs the full gate
     nightly. Add test-lab, test-fixtures or test-release when the change
     reaches them, and run only the UI or app tests the change touches. -->

```sh
mise run check
```

CI (`verify`) green on the pull request's latest push.

## Depends on

<!-- Issues or tasks that must be merged first, or "none". -->

## Branch and model

- Branch: `task/<id>-<slug>`
- Model: default | general

## Stop and ask if

- a choice belongs to the product owner or contradicts the PRD
- the acceptance criteria cannot be met as written
- <task-specific conditions>
