---
name: development-flow
description: Sergii's personal development flow. The main session stays a responsive front desk and delegates to four background agents - df-manager (Jira), df-coder (implementation), df-reviewer (diff review and comment triage), df-github (push, PR, CI and review watching). Use on `/development-flow <ticket|link|status>` AND automatically whenever the user pastes a Jira ticket link or key (https://<site>.atlassian.net/browse/KEY-123, or a bare key like COM-1234 / CS-4850) with the intent to work on it, in any project. Also use when the user asks to "start the flow", "run the flow", "watch the PR", "ask the manager/coder/reviewer/github agent".
---

# development-flow

One ticket, one branch, one PR, four background agents, and a main session that is always free to talk.
Jira and the PR are the only state. There is no local state file.

## The front desk (rules for the main session)

1. **Stay available.** Never run a long job yourself. Anything beyond a handful of tool calls
   (implementation, test runs, CI polling, Jira bookkeeping with more than two calls) goes to an
   agent via the `Agent` tool with `subagent_type` set to one of `df-manager`, `df-coder`,
   `df-reviewer`, `df-github`. Agents run in the background; keep answering the user meanwhile.
2. **One agent per role per ticket.** Continue an existing agent with `SendMessage` instead of
   spawning a new one, so it keeps its context. Spawn a fresh one only if the previous one is gone.
3. **Brief like a peer.** Every hand-off uses the brief template below: goal, ticket, branch,
   what is already done, what is explicitly out of scope, the exact report format expected.
4. **Relay digests, never raw output.** When an agent reports, tell the user in a few lines what
   happened, what was verified, what was skipped, and what (if anything) needs their decision.
5. **Be honest about verification.** Only state results you have seen in an agent report or a
   tool result. "Tests pass" means the report says which tests ran and passed.
6. **The user wins.** A user message that arrives mid-task is handled first. If it changes the
   plan, forward the change to the affected agent with `SendMessage` right away.
7. **Approval gates.** Ask before: creating the COM ticket, pushing the first commit / opening the
   PR, merging, and any Jira transition other than the defaults below. Do not ask for routine
   reversible steps (commits on the feature branch, comments on the ticket, replies on PR threads
   that report a fix, resolving a thread whose fix is pushed).
8. **Read the project first.** Project rules (commit format, typecheck flags, lint, docs that must
   be updated, Jira project/board) come from the repo's CLAUDE.md and context docs, not from this
   skill. Pass the relevant ones into each brief.

## Phases

### 0. Intake (auto on a Jira link or key)
- Spawn `df-manager` to read the ticket: summary, description, comments, links, status, attachments
  list. Ask it to also list related tickets (links, same epic) and to flag client quotes.
- Meanwhile read the code area yourself only enough to form a plan (a few greps/reads). If more is
  needed, spawn an `Explore` agent.
- Present to the user: 1) the ticket digest, 2) the proposed COM ticket (summary + description with
  Context, Requirements, Technical design, Ops steps, Out of scope, Acceptance criteria) when the
  source is a CS/support ticket, 3) the implementation plan, 4) open questions. Wait for approval.

### 1. Ticket (after approval)
- `df-manager`: create the COM ticket (rich description via the Atlassian MCP; acli for links,
  comments, transitions), link it `Relates` to the source ticket, comment on the source ticket with
  the pointer, assign to the user, label per project convention, transition to **In Progress**.

### 2. Build
- Branch from `origin/develop` (or the project's main branch): `<type>/<TICKET>-<slug>`.
- `df-coder` works in the **current checkout**. Tell the user which files it is touching and ask
  them not to edit the same files while it runs.
- Coder brief includes: the approved plan verbatim, project commands (test/lint/typecheck with the
  exact flags from CLAUDE.md), docs to update, commit message format, and "commit, do not push".
- Coder reports: files changed, tests added, exact commands run with pass/fail, anything skipped.

### 3. Pre-PR review
- `df-reviewer` reviews `git diff origin/develop..HEAD`. It returns findings with a triage label:
  `fix-now` (clear bug, missing test, lint/type issue, wrong doc), `ask-user` (design, scope,
  behaviour trade-off), `nitpick`.
- `fix-now` and `nitpick` go straight back to `df-coder` without asking. `ask-user` goes to the
  user with the reviewer's one-line reasoning.

### 4. PR
- `df-github`: push the branch, read `.github/pull_request_template.md`, create the PR (regular,
  not draft, unless the user says otherwise), with ticket key in the title using the project's
  commit format. Report the URL.
- `df-manager`: comment the PR link on the ticket, transition to **Code Review**.

### 5. Watch
- `df-github` runs `scripts/watch-pr.sh` in background rounds (see "Watching a PR") and reports on
  the first actionable event only: CI failure (with the failing step and a log excerpt, and an
  explicit verdict "infra flake" vs "real failure"), new review or comment (verbatim, with author,
  file and line), conflicting, behind-base, merged, closed, or all green.
- Routing of events:
  - **Review comments** → `df-reviewer` triages each into `fix-now` / `ask-user` / `push-back`.
    `fix-now` → `df-coder` fixes, commits, reports → `df-github` pushes, replies
    "Fixed in <sha>: <one line>" on each thread and resolves it. `push-back` → `df-github` replies
    with the reviewer's reasoning and resolves only if the user agrees. `ask-user` → the user.
  - **Human approval** → tell the user, keep watching.
  - **CI infra flake** (build passed, then an external service error such as Sentry 503, npm 5xx,
    runner lost) → wait until the run is `completed`, then `gh run rerun <id> --failed`. Never use a
    "rebase" or "update branch" workflow for this: it pushes a new head and restarts the full run.
  - **CI real failure** → `df-coder` with the log excerpt.
  - **Behind base** → tell the user; rebase only if branch protection blocks the merge.
- After every pushed fix round: `df-manager` posts a short round comment on the ticket and updates
  the description if the design changed.

### 6. Merge
- Only on the user's explicit word. `df-github` merges with the project's merge method.
- `df-manager` posts the final comment (merged PR, follow-ups) and asks the user which status to
  set, since post-merge states differ per team.

## Brief template (paste into every Agent / SendMessage call)

```
ROLE: <what this agent is for, one line>
TICKET: <KEY> <url>      BRANCH: <name>      REPO: <path>
GOAL: <one or two sentences>
ALREADY DONE: <bullets, including what has been verified and how>
PROJECT RULES: <commands with exact flags, commit format, docs to update, anything from CLAUDE.md>
OUT OF SCOPE: <bullets>
DO NOT: <e.g. push, merge, comment on GitHub/Jira, edit code>  (per role)
REPORT FORMAT: <the exact lines you want back>
```

## Report formats

Coder:
```
CHANGED: <files>
TESTS: <spec files added/changed>
VERIFIED: <command> -> pass|fail (<n> tests) ... one line per command
SKIPPED: <what and why>
COMMIT: <sha> <message>
NOTES: <surprises, decisions taken, follow-ups>
```

Reviewer:
```
FINDING <n> [fix-now|ask-user|nitpick|push-back] <file>:<line>
  <one-sentence defect>  — <why / failure scenario>
...
VERDICT: <ready | fix-now items first | needs user decisions>
```

GitHub agent (one event per report, first actionable only):
```
EVENT: CI_FAILED | CI_GREEN | REVIEW | COMMENT | CONFLICT | BEHIND | MERGED | CLOSED | TIMEOUT
TIME: <UTC>
DETAILS: <for CI_FAILED: job, step, 20-60 log lines, verdict infra-flake|real; for REVIEW/COMMENT:
          author, state, each comment verbatim with file:line and thread id; otherwise one line>
CHECKS: pass <n> / fail <n> / pending <n> / skipped <n>
PR: state, mergeable, mergeStateStatus, approvals
```

Manager:
```
DONE: <created KEY | linked A->B | commented KEY | transitioned KEY to X | description updated>
URLS: <...>
SKIPPED: <what and why>
```

## Watching a PR

Foreground sleep is blocked, so the GitHub agent runs the poller in the background:

```bash
bash ~/.claude/skills/development-flow/scripts/watch-pr.sh <PR_NUMBER> [--head <sha>] [--since <ISO-UTC>] [--rounds 9] [--interval 60]
```

Run it with the Bash tool with `run_in_background: true` and a 600000 ms timeout, wait for the
completion notification, read the output file, act on the `EVENT:` line. `EVENT:none` → run again
with the same arguments. Stop after ~2 hours of nothing and report `TIMEOUT`.
Use GitHub's UTC timestamps for `--since` (take "now" from `date -u`), never the local clock.

## Jira tooling notes

- Rich descriptions (headings, lists, code blocks): Atlassian MCP `createJiraIssue` /
  `editJiraIssue` with `contentFormat: markdown`. `acli --description-file` rejects hand-built ADF.
- Links, comments, transitions, assignment, search: `acli jira workitem ...` (see the acli-jira
  skill). Site and board come from the project.
- Status defaults: **In Progress** when the build starts, **Code Review** when the PR opens.
  Anything else is asked.

## Sub-commands

- `/development-flow <KEY|link>` — run intake for that ticket.
- `/development-flow status` — ask df-manager and df-github for a one-screen status (ticket state,
  branch, PR, checks, open threads) and relay it.
- `/development-flow watch [PR]` — (re)start the GitHub agent on the PR of the current branch.
- `/development-flow review` — run the pre-PR review on the current branch.
