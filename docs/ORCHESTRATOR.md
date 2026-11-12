# Orchestrator guide

How the Clove orchestrator routes work to machines and workers with T3 Code,
and what it does with each result. The orchestrator performs the supervisor
role in [docs/AGENT-WORKFLOW.md](AGENT-WORKFLOW.md): task issues, workers,
review, merge, releases.

mmq-mode owns the task workflow itself: sizing, process, verification, and
the PR handoff. This guide does not repeat it and creates no second
workflow. Repository constraints live in [AGENTS.md](../AGENTS.md); process
and merge policy live in [docs/AGENT-WORKFLOW.md](AGENT-WORKFLOW.md). Where
those files speak, they win. So do the owner's current requests and the
tools' own contracts, which change; this guide records how to work with
them, not a frozen snapshot.

## A task, end to end

1. Choose the destination machine from the table below, and verify the
   environment, project, and model catalog live before routing.
2. Start the work: a delegate for subordinate work; a new top-level thread
   only when the user asks for one or the work needs its own checkout.
3. Brief the worker with the issue, the checks, and mmq-mode discovery.
4. Take the result through T3; never poll.
5. Re-read the issue, review the diff, run the Linux compile gate.
6. Merge when the gate passes; record supervisor decisions on issue #150.
7. Release only from the Mac mini, only with the owner's upload
   authorization.

## Machines and projects

| Machine | T3 environment | Clove project | Checkout | SSH | Used for |
| --- | --- | --- | --- | --- | --- |
| Linux orchestrator (this machine) | `52d2b9be-8ee4-4b39-bba4-943a174ff059` | `c773872d-978a-48d2-99e6-f0665c4e7140` | `/data/Workspace/t3ws/projects/cloveapp` | — | routing, review, merge, the Linux compile gate; no Darwin builds, tests, simulators, or releases |
| Mac mini ("Shiny's Mac mini") | `99357d1a-e0bf-475f-a9c0-d494ddd3b182` | `mcp:9f0bab0d-27c9-4208-9f01-c745966f7476` | `/Volumes/T7/Projects/cloveapp`; T3 worktrees under `~/.t3/worktrees/cloveapp`, a symlink onto the T7 | `macmini-home` | builds, simulator tests, TestFlight releases; signing material lives here |
| MacBook Air ("Tony's MacBook Air") | `355a00f7-76d9-4c69-b52d-407cab78dabc` | `mcp:a6c326f3-30e6-4ef4-a94d-1856d24c26de` | `/Users/tony.liu/Projects/cloveapp` | `mba-tailnet` | second worker Mac; a laptop, so often unreachable; no signing material |

These IDs were recorded in November 2026 and are routing references, not
truth. Before routing, confirm each one live: list linked environments and
their reachability, read the project on the destination, and read the
destination's model catalog (`orchestrator_capabilities`). A machine that is
unreachable now may rejoin later; do not silently reroute its work to
another machine.

Machine notes:

- New T3 checkouts may need `mise trust` before mise tasks run.
- Fixture sets are built per machine on first need: `mise run fixtures-sets`.
- The Mini's repository lives on the T7 external drive. If the drive is
  unmounted, worker launches fail until it is back.
- CLI tools on the Macs come from mise, not Homebrew. A non-interactive SSH
  shell does not load mise; check `~/.local/share/mise/shims`. On the Air,
  `/opt/homebrew/bin` may also be needed on `PATH`.
- `gh auth status` over SSH on a Mac can report "invalid" because the token
  sits in the keychain. Test `gh` from inside a worker context, not an SSH
  shell.

A launch names the destination explicitly. Compact example for the Mac mini;
the model value is a placeholder, picked from the live catalog (next
section):

```json
{
  "title": "[C7] Group engine",
  "message": "Read issue #123, AGENTS.md, and the plan rows it references. Use /skill:mmq-mode; the repository wins on conflict, and you report the conflict in the PR.",
  "environmentId": "99357d1a-e0bf-475f-a9c0-d494ddd3b182",
  "projectId": "mcp:9f0bab0d-27c9-4208-9f01-c745966f7476",
  "workspaceStrategy": { "type": "worktree", "baseRef": "origin/main", "startFromOrigin": true },
  "runtimeMode": "full-access",
  "modelSelection": { "provider": "pi", "instanceId": "pi", "model": "<exact catalog ID for this role and destination>" }
}
```

## Worker models

There is no permanent default model. For each worker, pick a model that
exists in the destination environment's catalog and matches the owner's
current preference for that role. Never guess a provider prefix
(`magpie/office/…`, `magpie/remote-magpie/…`), and never switch a running
worker's model silently: catalogs differ per environment, and a model that
exists on one machine may not exist on another.

Dated references, not defaults:

- 2026-11-12, Mac mini: `magpie/office/group/general` with `thinking: high`
  was used for UI design-to-code workers. An older Flash default had already
  been superseded by per-task choice.
- 2026-11-12, MacBook Air: `magpie/remote-magpie/group/general`.
- 2026-12, this Linux orchestrator worker: `magpie/group/ps-fast`; the Air's
  catalog carried `magpie/remote-magpie/group/ps-fast`.

A model or provider change takes effect on the worker's next run, never
midway through the current one. A thread's model is readable and settable
with `t3_thread_configure`, and the same rule applies to a change made
there. To move active work now, stop the run with the tool that owns it
(`t3_thread_interrupt` for a top-level thread's run, `task_cancel` for a
delegate), send the work again with the new model, and have the worker clean
up anything the stopped run left, such as simulators or watchers.

## Starting work

- Subordinate work (a review, a focused check, a small follow-up) goes
  through `delegate_task`, with `isolation: "worktree"` where supported.
- `t3_thread_launch` creates a new top-level thread only when the user asks
  for one, or when the work needs its own checkout that delegation cannot
  provide. Bind the checkout with `workspaceStrategy`. Independent work
  starts from `origin/main` with `startFromOrigin`; dependent or stacked
  work starts from its explicit base instead, preserved.
- If a destination does not support delegated worktree isolation, do not
  fall back to the shared root checkout silently: use a launched thread with
  a worktree, or say why the work cannot start.
- Never create a worker checkout with shell `git` commands; checkouts come
  from the tools.
- Capacity: at most two workers per Mac, and at most one of them doing
  simulator work.

## Briefing a worker

Every brief names:

- the issue number, as the full scope. Issues are living documents; the
  owner and designers update them while work runs.
- the expected deliverables: pull request, head SHA, checks, evidence. The
  worker delivers a PR and never merges.
- the checks to run, linked from the task table in
  [AGENTS.md](../AGENTS.md#tasks) rather than copied into the brief.
- mmq-mode discovery: start with `/skill:mmq-mode`; if the skill is not
  autoloaded, read `SKILL.md` under
  `~/.local/share/pi-packages/*/package/skills/mmq-mode/`. Repository
  instructions win on conflict; the worker reports the conflict in its PR.
- what the worker owns: its simulator device and build output inside its own
  checkout ([AGENTS.md](../AGENTS.md#build-output-and-simulators)).
- the report format: the STATUS block defined in
  [docs/AGENT-WORKFLOW.md](AGENT-WORKFLOW.md#4-report-worker).

## Taking results

- Keep the `taskId` and thread link from the launch result, and follow any
  `next` the tool returns.
- Do not poll running work: no `task_status` loops, sleeps, or watchers.
  Completion arrives on its own; read the result once the run is finished.
- Steering an implementation thread that is already running goes through
  `t3_thread_send`. A review is not steering: start a fresh delegate with
  the diff and the issue.
- Stop a delegate you replace or no longer need with `task_cancel`; it ends
  the delegate's running and queued turns and its child work.

## Review, fix rounds, and merge

Follow [docs/AGENT-WORKFLOW.md](AGENT-WORKFLOW.md#task-lifecycle) for the
lifecycle and [AGENTS.md](../AGENTS.md) for what each change must check.
Clove-specific practice on top of them:

- Re-read the issue before reviewing; it may have changed under the PR.
- The orchestrator reads every diff itself. The second-model review stays
  limited to the cases AGENT-WORKFLOW lists (mark writes, XMP, large UI),
  and it is a fresh delegate briefed with the diff, the issue, and the plan
  areas due for rewrite.
- Triage findings before any fix round: fix now, hold as requirements on the
  planned task that will rewrite the code, or drop. Send only the fix-now
  list, and say what was held and why.
- One fix round, then merge when the gate passes. Park later review findings
  as new issues instead of looping rework. A real data-loss defect still
  blocks the merge.
- The gate is the light one documented in
  [AGENT-WORKFLOW.md](AGENT-WORKFLOW.md#6-merge): review, the worker's
  `mise run check`, and the Linux compile gate below. No merge waits for the
  full suite or a simulator, and nothing is re-run because `main` moved.
  Nightly failures become issues.
- The orchestrator squash-merges from this Linux machine:
  `gh pr merge <number> --squash --delete-branch --match-head-commit <sha>`.

## Supervisor decisions

Decisions the orchestrator makes on its own (scope calls, deviations
accepted, ordering) are recorded as comments on issue
[#150](https://github.com/mimiqdev/cloveapp/issues/150) for the owner to
check later. Owner decisions stay in issues and
`design/handoff/decisions-log.md`. Use that issue; do not start a new
ledger.

## On this Linux machine

- `/data/Workspace/build/clove-linux-check.sh <ref>` is the compile gate:
  strict `swift format lint`, the three packages cross-compiled for iOS, and
  the Clove app target type-checked against the iOS SDK with Swift 6 and
  complete strict concurrency. Around 25 seconds; exits nonzero on any
  failure.
- It runs no tests, so a pass never means tests passed: CloveCore and the
  app cannot run here. Darwin-side work (tests, simulators, screenshots,
  releases) does not happen on this machine.
- The script is external to the repository and shares scratch space and a
  detached worktree under `/data/Workspace/build`. Run it serially, one ref
  at a time.
- `main` type-checks with zero warnings; a new warning on a pull request is
  a finding.
- Git pushes go over SSH. `gh`'s OAuth token here has no `workflow` scope,
  so an HTTPS push of workflow files is refused; push over SSH instead of
  detouring through a Mac.

## TestFlight releases

Releases run on the Mac mini only, from a clean checkout of merged `main`,
following [docs/release.md](release.md). The operational points:

- The release config lives at `~/.config/apple/clove-testflight.json` on the
  Mini and is used in place: the script reads it where it lies. Never print,
  copy, move, or commit the config or any file it names.
- ```sh
  mise run release -- --config ~/.config/apple/clove-testflight.json --app clove
  ```
- `--upload` happens only when the owner authorized that specific upload.
- A run has distinct end states: validation can pass with nothing uploaded;
  an upload that `altool` accepted is still not visible until App Store
  Connect finishes processing. Report which state was reached, not
  "released".

Duo simulator pose automation
([#197](https://github.com/mimiqdev/cloveapp/issues/197)) is in progress.
When it lands, link its helper script and its own guide for
graphical-session and Accessibility setup; this guide records none of that.
