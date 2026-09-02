#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): block a real `gh pr create` for THIS repo
# until the finish pipeline has left its evidence — a green ci-verifier
# marker for the current HEAD, and a code-reviewer report for this branch in
# the sibling vault.
#
# Deterministic enforcement half of the finish pipeline. Wired from
# .claude/settings.json. See AGENTS.md "Auto-run wiring".
set -uo pipefail

payload="$(cat)"
if command -v jq >/dev/null 2>&1; then
  cmd="$(jq -r '.tool_input.command // empty' <<<"$payload")"
else
  cmd="$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' <<<"$payload")"
fi

# `gh pr create` as an actual command (line start / after ; & | && || / newline),
# not the phrase quoted in a commit message or echo.
printf '%s' "$cmd" | grep -qE '(^|[;&|]|[[:cntrl:]])[[:space:]]*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0

# This hook belongs to one repo — the project dir Claude Code launched in.
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$root" ] && cd "$root" || exit 0

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
head_sha="$(git rev-parse HEAD 2>/dev/null || true)"

# If the command targets a different branch/repo (--head X where X isn't our
# branch), it's not our PR to guard.
headarg="$(printf '%s' "$cmd" | sed -n 's/.*--head[ =]\([^ ]*\).*/\1/p')"
[ -n "$headarg" ] && [ "$headarg" != "$branch" ] && exit 0

missing=""
marker=".git/ci-verifier-pass"
if [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null)" != "$head_sha" ]; then
  missing="${missing}- ci-verifier has not passed green for the current HEAD (${head_sha:0:8}). Spawn ci-verifier (and ci-fixer-agent if red) first.\n"
fi

sessions_dir="../golden-fur-vault/Projects/golden-fur/sessions"
if [ -n "$branch" ]; then
  # the session folder whose plan.md / testing.md names this branch
  sess="$(grep -rl -F "$branch" "$sessions_dir"/*/plan.md "$sessions_dir"/*/testing/testing.md 2>/dev/null \
            | sed -E 's#(.*/sessions/[^/]+)/.*#\1#' | sort -u | head -1)"
  if [ -z "$sess" ] || ! ls "$sess"/reviews/*.md >/dev/null 2>&1; then
    missing="${missing}- no code-reviewer report for branch ${branch} in its sessions/<NN-slug>/reviews/ folder. Spawn code-reviewer (trigger pre-pr) first.\n"
  fi
fi

[ -z "$missing" ] && exit 0

reason="pr-guard: the finish pipeline's evidence is missing, so this PR is not ready:\n${missing}\nRun the steps the session-router hook listed, then retry."
if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$(printf '%b' "$reason")" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python -c 'import json,sys;print(json.dumps(sys.stdin.read()))' <<<"$(printf '%b' "$reason")")"
fi
exit 0
