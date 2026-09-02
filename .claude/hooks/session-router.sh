#!/usr/bin/env bash
# UserPromptSubmit hook: deterministically route the session by what the user
# just asked for. Decides only; injects guidance as additionalContext - the
# probabilistic skills/agents still do the work. Never blocks the prompt.
#
# Vault side: this repo has a single `main` branch and a single `pr` skill.
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
  emit "SESSION-FINISH MODE (session-router hook). Vault pipeline, in order:
1. branch: if HEAD is main, run \`branch-naming\` to create+push a branch.
2. verify: spawn \`ci-verifier\` (both repos - vault format:check + golden-fur's suite if it changed).
3. ci-fixer: if red, spawn \`ci-fixer-agent\`, re-verify until green.
4. session/Reference: confirm the sessions/ + Reference/ material for this session is written (session-documenter / workflow-documenter ran already) - write/update if not.
5. commit: run the \`commit\` skill.
6. push.
7. PR: the \`pr\` skill (targets main, merge commit).
The \`pr-guard\` hook blocks \`gh pr create\` until step 2 is green for HEAD."
  exit 0
fi

exit 0
