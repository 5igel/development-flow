#!/usr/bin/env bash
# watch-pr.sh — poll a GitHub PR and exit on the first actionable event.
#
# Usage: watch-pr.sh <PR_NUMBER> [--head <sha>] [--since <ISO-UTC>] [--rounds N] [--interval S] [--ignore-green]
#   --ignore-green  do not exit on CI_GREEN (use when CI is already green and you wait for reviews/merge)
#
# Prints one EVENT line (plus details) and exits 0:
#   EVENT:CI_FAILED | CI_GREEN | REVIEW | COMMENT | CONFLICT | BEHIND | MERGED | CLOSED | none
# Comments/reviews by the authenticated user are ignored. Runs inside the repo (uses gh's repo detection).
set -euo pipefail

PR=${1:?PR number required}; shift || true
HEAD=""; SINCE=""; ROUNDS=9; INTERVAL=60; IGNORE_GREEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --head) HEAD=$2; shift 2;;
    --since) SINCE=$2; shift 2;;
    --rounds) ROUNDS=$2; shift 2;;
    --interval) INTERVAL=$2; shift 2;;
    --ignore-green) IGNORE_GREEN=1; shift;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
ME=$(gh api user --jq .login)
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -z "$HEAD" ] && HEAD=$(gh pr view "$PR" --json headRefOid --jq .headRefOid)
[ -z "$SINCE" ] && SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "WATCH pr=$PR head=${HEAD:0:9} since=$SINCE rounds=$ROUNDS interval=${INTERVAL}s me=$ME"

for i in $(seq 1 "$ROUNDS"); do
  now=$(date -u +%H:%M:%SZ)
  pr=$(gh pr view "$PR" --json state,mergeable,mergeStateStatus,headRefOid,reviewDecision,statusCheckRollup 2>/dev/null) || { echo "round $i $now: gh error, retrying"; sleep "$INTERVAL"; continue; }
  state=$(jq -r .state <<<"$pr"); cur=$(jq -r .headRefOid <<<"$pr")
  mergeable=$(jq -r .mergeable <<<"$pr"); mss=$(jq -r .mergeStateStatus <<<"$pr")
  checks=$(jq -r '[.statusCheckRollup[]? | {n:(.name // .context), s:(.status // ""), c:(.conclusion // .state // "")}]' <<<"$pr")
  fail=$(jq '[.[] | select((.c|ascii_upcase) as $c | $c=="FAILURE" or $c=="TIMED_OUT" or $c=="CANCELLED" or $c=="ERROR")] | length' <<<"$checks")
  pending=$(jq '[.[] | select((.s|ascii_upcase)!="COMPLETED" and (.c|ascii_upcase)!="SUCCESS" and (.c|ascii_upcase)!="SKIPPED" and (.c|ascii_upcase)!="NEUTRAL" and (.c|ascii_upcase)!="FAILURE")] | length' <<<"$checks")
  ok=$(jq '[.[] | select((.c|ascii_upcase)=="SUCCESS")] | length' <<<"$checks")
  skipped=$(jq '[.[] | select((.c|ascii_upcase)=="SKIPPED" or (.c|ascii_upcase)=="NEUTRAL")] | length' <<<"$checks")
  summary="CHECKS: pass $ok / fail $fail / pending $pending / skipped $skipped
PR: state=$state mergeable=$mergeable mergeStateStatus=$mss head=${cur:0:9}"

  if [ "$state" = "MERGED" ]; then echo "EVENT:MERGED"; echo "$summary"; exit 0; fi
  if [ "$state" = "CLOSED" ]; then echo "EVENT:CLOSED"; echo "$summary"; exit 0; fi
  if [ "$cur" != "$HEAD" ]; then echo "EVENT:NEW_HEAD"; echo "head moved from ${HEAD:0:9} to ${cur:0:9}"; echo "$summary"; exit 0; fi

  reviews=$(gh api "repos/$REPO/pulls/$PR/reviews" --paginate | jq -s 'add // []' | jq --arg s "$SINCE" --arg me "$ME" '[.[] | select(.submitted_at > $s and .user.login != $me and ((.body // "") | test("configured for manual code reviews") | not)) | {id, user: .user.login, state, at: .submitted_at, body: (.body|.[0:400])}]')
  rcomments=$(gh api "repos/$REPO/pulls/$PR/comments" --paginate | jq -s 'add // []' | jq --arg s "$SINCE" --arg me "$ME" '[.[] | select(.created_at > $s and .user.login != $me) | {id, user: .user.login, at: .created_at, path, line: (.line // .original_line), in_reply_to: .in_reply_to_id, body}]')
  icomments=$(gh api "repos/$REPO/issues/$PR/comments" --paginate | jq -s 'add // []' | jq --arg s "$SINCE" --arg me "$ME" '[.[] | select(.created_at > $s and .user.login != $me) | {id, user: .user.login, at: .created_at, body}]')
  nrev=$(jq length <<<"$reviews"); nrc=$(jq length <<<"$rcomments"); nic=$(jq length <<<"$icomments")
  if [ "$nrev" -gt 0 ] || [ "$nrc" -gt 0 ] || [ "$nic" -gt 0 ]; then
    if [ "$nrc" -gt 0 ] || [ "$nic" -gt 0 ]; then echo "EVENT:COMMENT"; else echo "EVENT:REVIEW"; fi
    echo "TIME: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "REVIEWS: $reviews"; echo "REVIEW_COMMENTS: $rcomments"; echo "ISSUE_COMMENTS: $icomments"
    echo "$summary"; exit 0
  fi

  if [ "$fail" -gt 0 ]; then
    echo "EVENT:CI_FAILED"; echo "TIME: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -r '.[] | select((.c|ascii_upcase) as $c | $c=="FAILURE" or $c=="TIMED_OUT" or $c=="CANCELLED" or $c=="ERROR") | "FAILED: \(.n)"' <<<"$checks"
    gh run list --commit "$cur" --json databaseId,name,status,conclusion --jq '.[] | "RUN: \(.databaseId) \(.name) \(.status) \(.conclusion // "-")"' 2>/dev/null || true
    echo "$summary"; exit 0
  fi
  if [ "$mergeable" = "CONFLICTING" ]; then echo "EVENT:CONFLICT"; echo "$summary"; exit 0; fi
  if [ "$IGNORE_GREEN" -eq 0 ] && [ "$pending" -eq 0 ] && [ "$ok" -gt 0 ]; then
    echo "EVENT:CI_GREEN"; echo "$summary"
    [ "$mss" = "BEHIND" ] && echo "NOTE: branch is behind base (mergeStateStatus=BEHIND)"
    exit 0
  fi
  echo "round $i/$ROUNDS $now: pass $ok fail $fail pending $pending mss=$mss"
  [ "$i" -lt "$ROUNDS" ] && sleep "$INTERVAL"
done
echo "EVENT:none"; echo "$summary"
