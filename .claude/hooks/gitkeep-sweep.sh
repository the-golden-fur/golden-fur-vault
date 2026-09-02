#!/usr/bin/env bash
# Stop hook: keep .gitkeep placeholders honest.
#   ADD    an empty .gitkeep to an on-disk directory that is otherwise empty
#          and that git does not ignore (so the dir survives a clone).
#   REMOVE a .gitkeep from a directory that now has other files.
# Idempotent; stages its own changes. Conservative — if it can't confirm a
# dir is in-scope it leaves it alone.
#
# Wired from .claude/settings.json (Stop). See AGENTS.md "Auto-run wiring".
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
changed=0

# --- ADD --------------------------------------------------------------------
# Empty dirs, with .git and any node_modules pruned outright.
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -d "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ] || continue
  # git must NOT ignore it (check-ignore exit 0 = ignored -> skip)
  git check-ignore -q "$d" 2>/dev/null && continue
  : > "$d/.gitkeep"
  git add "$d/.gitkeep" >/dev/null 2>&1 || true
  changed=1
done < <(find . -type d \
           \( -name .git -o -name node_modules \) -prune -o \
           -type d -empty -printf '%P\n' 2>/dev/null)

# --- REMOVE ----------------------------------------------------------------
# Dirs that hold a .gitkeep AND at least one other tracked/addable file.
while IFS= read -r d; do
  [ -n "$d" ] && [ -f "$d/.gitkeep" ] || continue
  git rm -q --ignore-unmatch "$d/.gitkeep" >/dev/null 2>&1 || rm -f "$d/.gitkeep"
  changed=1
done < <(
  { git ls-files; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u \
  | awk -F/ '
      { if (NF < 2) dir="."; else { dir=$1; for (i=2;i<NF;i++) dir=dir"/"$i }
        if ($NF==".gitkeep") { if (!(dir in o)) o[dir]=0; k[dir]=1 } else o[dir]++ }
      END { for (d in k) if (o[d]+0 > 0) print d }'
)

[ "$changed" -eq 0 ] && exit 0

msg=".gitkeep sweep (from .claude/hooks): adjusted placeholder file(s) so empty tracked dirs stay in git and non-empty ones don't carry a stray .gitkeep. Staged with your changes."
if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$msg" '{systemMessage: $m}'
else
  printf '{"systemMessage": %s}\n' "$(python -c 'import json,sys;print(json.dumps(sys.stdin.read()))' <<<"$msg")"
fi
