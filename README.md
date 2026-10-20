# development-flow

A personal [Claude Code](https://claude.com/claude-code) workflow: one Jira ticket, one branch,
one PR, four background agents, and a main session that stays free to talk.

Jira and the PR are the only state. There is no local state file.

## What is in here

```
skills/development-flow/SKILL.md            the flow: front-desk rules, phases, brief and report templates
skills/development-flow/scripts/watch-pr.sh  PR poller: exits on the first actionable CI / review / merge event
agents/df-manager.md                         Jira bookkeeping (read, create, link, comment, transition)
agents/df-coder.md                           implements the approved plan, tests, commits (never pushes)
agents/df-reviewer.md                        read-only diff review and triage of PR comments
agents/df-github.md                          push, PR, CI watching, review threads, merge on request
install.sh                                   symlinks everything into ~/.claude
```

## How it works

The main session is a front desk. It reads the ticket, proposes a plan, and after approval hands
every long job to a background agent via the `Agent` tool (`subagent_type: df-*`). Agents report
in fixed formats; the front desk relays digests and asks the user only at approval gates
(creating the implementation ticket, first push / PR, merge, non-default Jira transitions).

Phases: intake → ticket → build → pre-PR review → PR → watch (CI, reviews, fix rounds) → merge.
Details, templates and report formats are in [`SKILL.md`](skills/development-flow/SKILL.md).

## Install

```bash
git clone https://github.com/5igel/development-flow.git
cd development-flow
./install.sh          # symlinks; `./install.sh --copy` to copy instead
```

Existing files at the target paths are moved aside with a `.bak.<timestamp>` suffix.
Start a new Claude Code session afterwards.

## Requirements

- Claude Code with the `Agent` / `SendMessage` tools (background subagents).
- `gh` CLI, authenticated, for `watch-pr.sh` and the `df-github` agent.
- `acli` (Atlassian CLI) and the Atlassian MCP server for the `df-manager` agent.
- Project-level rules (commit format, test / lint / typecheck commands, Jira project) are read
  from each repo's `CLAUDE.md`; the skill carries none of its own.

## Usage

- `/development-flow <KEY|link>` — intake for a ticket. Pasting a Jira link or key with intent
  to work on it triggers the flow automatically.
- `/development-flow status` — one-screen status of ticket, branch, PR, checks, open threads.
- `/development-flow watch [PR]` — (re)start the GitHub agent on the current branch's PR.
- `/development-flow review` — pre-PR review of the current branch.

### watch-pr.sh standalone

```bash
bash skills/development-flow/scripts/watch-pr.sh <PR> [--head <full-sha>] [--since <ISO-UTC>] \
  [--rounds 9] [--interval 60] [--ignore-green]
```

Prints one `EVENT:` line (`CI_FAILED | CI_GREEN | REVIEW | COMMENT | CONFLICT | BEHIND | NEW_HEAD |
MERGED | CLOSED | none`) and exits. Pass the full head sha, not a short one. Use `--ignore-green`
once CI is already green and you are waiting for reviews or the merge.

## License

MIT, see [LICENSE](LICENSE).
