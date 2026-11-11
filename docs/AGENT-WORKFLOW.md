# Agent workflow

How tasks in the [development plan](DEV-PLAN.md) move from a GitHub issue to a merged pull request. Code conventions and commands live in `AGENTS.md` (added by T0.2). This document covers who does what and how work is handed off.

## Roles

| Role | Who | Responsibilities |
| --- | --- | --- |
| Product owner | Human | Gate decisions (G1, G2, G3), product and scope questions, real-device checks, Apple account |
| Supervisor | Orchestrating agent, outside the Mac | Writes task issues, starts workers, reviews and verifies pull requests, merges them |
| Worker | Pi agent on the Mac mini | Implements one task in its own checkout, verifies it, opens a pull request, reports back |

## Environment

- **Host:** the Mac mini, linked to T3 at full access. Workers always run in `full-access` mode, so commands never wait for approval.
- **Repository:** `/Volumes/T7/Projects/cloveapp` on the T7 external SSD. Each worker gets its own checkout under `~/.t3/worktrees/cloveapp/`, which links to `/Volumes/T7/Projects/.t3-worktrees/cloveapp/`. The T7 must stay connected while workers run.
- **Tools** come from mise (`mise.toml` in the repository pins xcodegen). Run project commands through `mise run <task>` or `mise exec --`.
- **Build output** stays inside the checkout (`-derivedDataPath .build/DerivedData.noindex`; Spotlight skips folders ending in `.noindex`), so it lands on the T7 and is removed with the checkout.
- **Simulators:** each worker creates its own simulator device named `Clove <task ID>` and deletes it when done, so parallel test runs never share a device.
- **Signing** files live in `~/.config/apple/` on the Mac and are referenced from gitignored local config. They never enter the repository, a log, an issue, or a pull request.

## Models

| Work | Model |
| --- | --- |
| Default (size S and M tasks, fix-ups) | `magpie/office/group/auto-deepseek-v4-1-flash` |
| Spikes, size L tasks, anything the default model failed at once | `magpie/office/group/general` |

## Task lifecycle

### 1. Issue (supervisor)

Every task starts as a GitHub issue created from the [task template](../.github/ISSUE_TEMPLATE/task.md). The title is `[<ID>] <task name>`, for example `[T0.2] Repository skeleton`. The issue is the worker's complete brief: goal, scope, acceptance criteria, files to read, and the checks to run. The issue lists its dependencies, and the supervisor starts it only after they have merged. Before writing the issue's decisions, the supervisor puts every piece of state and failure handling the issue adds through the three questions in [AGENTS.md](../AGENTS.md#keep-it-simple), "Keep it simple", and cuts what fails them.

Labels: `task` or `spike`, plus `device` when real-device verification is needed, `blocked`, and `needs-decision`.

### 2. Start (supervisor)

The supervisor launches one T3 thread per task on the Mac mini:

- project `cloveapp`, worktree strategy, base `main`, branch `task/<id>-<slug>` (for example `task/t0.2-skeleton`)
- `full-access` mode and the model from the table above
- the first message names the issue and says: read the issue, `AGENTS.md`, and the plan rows it references, then do the task

At most **three workers run at once**, limited by the Mac's internal disk (simulators) and CPU.

### 3. Work (worker)

- Stay within the issue's scope. Open a new issue for anything outside it.
- Commit in small steps. Push the branch and open a pull request from the [template](../.github/pull_request_template.md), titled `[<ID>] <summary>` and containing `Closes #<issue>`.
- Run every check the issue lists and paste the real output, trimmed to the relevant lines, into the pull request. `mise run verify` includes the `CloveLabKit` probe tests (`mise run test-lab`).
- Never merge, never push to `main`, never force-push a branch someone else is working on, and never touch signing files beyond reading them through the configured paths.

**Stop and report** instead of guessing when:

- a choice belongs to the product owner or contradicts the PRD
- the acceptance criteria cannot be met as written
- a dependency is missing or broken
- the same check keeps failing after a reasonable attempt

### 4. Report (worker)

The worker's final message is the handoff. It ends with this block, filled in exactly:

```text
STATUS: done | blocked | needs-decision
TASK: <ID>
ISSUE: <issue URL>
PR: <pull request URL, or none>
HEAD: <latest commit SHA on the branch>
CHECKS:
- <check>: pass | fail | not run
DEVIATIONS: none | <what differs from the issue and why>
QUESTIONS: none | <numbered questions for the supervisor or product owner>
```

For `blocked` or `needs-decision`, the worker also comments the same block on the issue and adds the matching label.

### 5. Review (supervisor)

1. Read the diff against the issue's acceptance criteria and the PRD.
2. Ask whether each new state, branch or recovery path is needed ([AGENTS.md](../AGENTS.md#keep-it-simple), "Keep it simple"). When a finding sits inside machinery that isn't needed, the fix is to delete the machinery, not patch it.
3. Re-run the issue's checks in the worker's checkout on the Mac. The worker's pasted output is not enough on its own.
4. Then one of:
   - **Small problems:** the supervisor fixes them on the branch.
   - **Larger problems:** a new worker thread on the same checkout, briefed with the findings as a review comment on the pull request. Its report uses the same block.
   - **Product or scope questions:** go to the product owner. The issue gets `needs-decision`.

### 6. Merge

The supervisor squash-merges every pull request once review and verification pass, including documentation, tooling, and release configuration.

The product owner is involved only for decisions that are theirs to make:

- gate outcomes (G1, G2, G3), including which approach a spike decision in `docs/decisions/` adopts
- PRD changes, or any change to product scope or behavior the PRD does not settle
- anything that costs money or changes the Apple account beyond this app's bundle IDs, profiles, and TestFlight groups

Such pull requests wait for the product owner's approval in the pull request or the thread. The supervisor merges them after that.

### 7. Clean up (supervisor)

After the merge, remove the worker's checkout and simulator, delete the branch, and settle the T3 thread.

## Device verification

Tasks labeled `device` follow the Clove Lab loop in the [development plan](DEV-PLAN.md#real-device-verification). The worker builds the measurements into Clove Lab and writes the checklist into the pull request. The supervisor uploads a TestFlight build once the work is merged, and the product owner runs the checklist. The JSON report goes back on the issue.
