#!/usr/bin/env bash
# UserPromptSubmit hook: deterministically route the session by what the user
# just asked for. Decides only; injects guidance as additionalContext - the
# probabilistic skills/agents still do the work. Never blocks the prompt.
#
# Vault side: this repo has a single `main` branch and a single `pr` skill.
# The "open a PR" route is branch -> commit -> push -> open a draft PR; no
# CI / verify step - the user runs those manually.
# Mirrored from golden-fur/.claude/hooks/. See AGENTS.md "Auto-run wiring".
set -euo pipefail

payload="$(cat)"
if command -v jq >/dev/null 2>&1; then
  prompt="$(jq -r '.prompt // empty' <<<"$payload")"
else
  prompt="$(sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' <<<"$payload")"
fi
[ -z "$prompt" ] && exit 0

lc="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

emit() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$1" \
      '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(python -c 'import json,sys;print(json.dumps(sys.stdin.read()))' <<<"$1")"
  fi
}

if printf '%s' "$lc" | grep -qE "(^|[^a-z])(/plan|just plan|plan only|plan first|don'?t touch code|do not touch code|no code( yet)?|planning only)([^a-z]|$)"; then
  emit "PLAN-ONLY MODE (session-router hook). Use the \`plan\` skill (.agent/skills/plan.md) + the built-in \`Plan\` agent. Edit no code. Reserve the next NN from Projects/golden-fur/sessions/ + sessions/_legacy/{custom,issues}/ and write only Projects/golden-fur/sessions/NN-<slug>/plan.md, for a near-beginner. Stop after the plan."
  exit 0
fi

if printf '%s' "$lc" | grep -qE "(^|[^a-z])(/pr|open (a|the) pr|make (a|the) pr|create (a|the) pull request|raise (a|the) pr|pr this|ready to pr|let'?s pr|ship it|finish (up )?and pr)([^a-z]|$)"; then
  emit "OPEN-A-PR MODE (session-router hook). Run once, then hand back the PR link - do NOT run CI / format / verification checks and do NOT spawn any verifier/fixer subagent. The user runs those manually after the PR exists.
1. branch: if HEAD is main, run \`branch-naming\` to create+push a branch.
2. commit: run the \`commit\` skill for any outstanding work (skip if the tree is clean).
3. push.
4. PR: the \`pr\` skill - opens a DRAFT PR targeting main with title, body, labels, and assignee all set.
Then stop."
  exit 0
fi

exit 0
