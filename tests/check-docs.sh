#!/usr/bin/env bash
# Guardrail for issue #37: agents.md is an index, not a fact cache.
# Run locally before committing a doc change, and on every push in CI.
set -uo pipefail

BUDGET=170 # lines in agents.md
fail=0

lines=$(wc -l < agents.md)
if [ "$lines" -gt "$BUDGET" ]; then
  echo "agents.md is $lines lines (budget $BUDGET)."
  echo "  Client facts -> ../.agents/skills/wow-forever-api/references/<file>.md"
  echo "  Product verdicts -> docs/NN-*.md"
  fail=1
fi

# Every numbered doc must be indexed in agents.md, or it is invisible to the next agent.
for f in docs/[0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  grep -q "$(basename "$f")" agents.md || { echo "docs/$(basename "$f") is not indexed in agents.md"; fail=1; }
done

# Every docs/NN-*.md path mentioned anywhere must exist.
missing=$(grep -rhoE 'docs/[0-9]{2}-[a-z0-9-]+\.md' agents.md readme.md docs tests 2>/dev/null \
  | sort -u | while read -r ref; do [ -e "$ref" ] || echo "$ref"; done)
if [ -n "$missing" ]; then
  echo "dead doc references:"; echo "$missing" | sed 's/^/  /'
  fail=1
fi

# The routing table in agents.md names the skill's reference files. .agents is gitignored, so this
# half only runs in the workspace checkout.
if [ -d .agents/skills/wow-forever-api/references ]; then
  missing_refs=$(grep -oE 'references/[a-z-]+\.md' agents.md | sort -u \
    | while read -r r; do [ -e ".agents/skills/wow-forever-api/$r" ] || echo "$r"; done)
  if [ -n "$missing_refs" ]; then
    echo "agents.md points at skill references that do not exist:"; echo "$missing_refs" | sed 's/^/  /'
    fail=1
  fi
fi

[ "$fail" -eq 0 ] && echo "docs check ok (agents.md $lines lines, $(ls docs/[0-9][0-9]-*.md | wc -l) docs indexed)"
exit $fail
