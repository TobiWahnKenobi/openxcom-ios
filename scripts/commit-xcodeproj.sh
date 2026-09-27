#!/usr/bin/env bash
#
# commit-xcodeproj.sh — commit project.pbxproj without your signing identity.
#
# Xcode writes DEVELOPMENT_TEAM and the code signing identity straight into
# project.pbxproj, so that file is held under skip-worktree and can never be
# committed by accident. When you DO need to commit a genuine project change
# (adding a framework, repointing a subproject), this script:
#
#   1. copies your working file aside,
#   2. rewrites every signing value back to whatever is already committed,
#      so the commit shows no signing diff at all,
#   3. lifts skip-worktree, stages, commits, re-applies skip-worktree,
#   4. puts your working file back exactly as it was.
#
# Your file is restored even if the commit fails or you interrupt it.
#
# Usage:
#   scripts/commit-xcodeproj.sh "Link CoreHaptics and GameController"
#   scripts/commit-xcodeproj.sh --check      # scrub-and-diff only, commit nothing
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUB="$REPO/Sources/OpenXcom"
REL="xcode-ios/OpenXcom.xcodeproj/project.pbxproj"
PBX="$SUB/$REL"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if [ "$CHECK_ONLY" -eq 0 ] && [ -z "${1:-}" ]; then
	echo "usage: $(basename "$0") \"commit message\"   |   $(basename "$0") --check" >&2
	exit 2
fi

[ -f "$PBX" ] || { echo "not found: $PBX" >&2; exit 1; }

STASHED="$(mktemp -t pbxproj.XXXXXX)"
cp "$PBX" "$STASHED"

restore() {
	cp "$STASHED" "$PBX"
	rm -f "$STASHED"
	# Always leave the file protected again, whatever happened above.
	git -C "$SUB" update-index --skip-worktree "$REL" 2>/dev/null || true
	echo "-- your working project.pbxproj restored, skip-worktree re-applied"
}
trap restore EXIT

# Rewrite signing values to the committed ones.
python3 - "$SUB" "$REL" <<'PY'
import re, subprocess, sys, pathlib

sub, rel = sys.argv[1], sys.argv[2]
path = pathlib.Path(sub) / rel

KEYS = ["DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE",
        "CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE", "CODE_SIGN_ENTITLEMENTS"]
LINE = re.compile(
    r'^(?P<lead>\s*"?(?P<key>' + "|".join(KEYS) + r')(?:\[[^\]]*\])?"?\s*=\s*)'
    r'(?P<val>.*?)(?P<tail>;\s*)$', re.M)

head = subprocess.run(["git", "-C", sub, "show", f"HEAD:{rel}"],
                      capture_output=True, text=True, check=True).stdout
work = path.read_text()

committed = {}
for m in LINE.finditer(head):
    committed.setdefault(m.group("key"), []).append(m.group("val"))

secrets, cursor = set(), {k: 0 for k in committed}
def swap(m):
    key, mine = m.group("key"), m.group("val")
    vals = committed.get(key, [])
    i = cursor.get(key, 0)
    if i >= len(vals):
        raise SystemExit(f"ABORT: working copy has more '{key}' entries ({i+1}) "
                         f"than the committed file ({len(vals)}). Resolve by hand.")
    cursor[key] = i + 1
    if mine != vals[i]:
        secrets.add(mine)
    return m.group("lead") + vals[i] + m.group("tail")

scrubbed = LINE.sub(swap, work)

# Refuse to continue if any of your values survived anywhere in the file.
leaked = [s for s in secrets if s and s.strip('"') and s.strip('"') in scrubbed]
if leaked:
    raise SystemExit(f"ABORT: {len(leaked)} signing value(s) still present after scrubbing.")

path.write_text(scrubbed)
n = sum(cursor.values())
print(f"-- scrubbed {n} signing entr{'y' if n == 1 else 'ies'} "
      f"({len(secrets)} differed from the committed values)")
PY

git -C "$SUB" update-index --no-skip-worktree "$REL"

if [ "$CHECK_ONLY" -eq 1 ]; then
	echo "-- diff that WOULD be committed:"
	git -C "$SUB" --no-pager diff --stat -- "$REL" | sed 's/^/   /'
	echo "-- signing lines in that diff (values masked; any shown are relocations,"
	echo "   not value changes -- yours were already replaced above):"
	git -C "$SUB" --no-pager diff -- "$REL" \
		| grep -E "^[+-].*(DEVELOPMENT_TEAM|PROVISIONING_PROFILE|CODE_SIGN)" \
		| sed -E 's/= [^;]*;/= <masked>;/' | sed 's/^/   /' \
		|| echo "   none"
	exit 0
fi

if git -C "$SUB" diff --quiet -- "$REL"; then
	echo "-- nothing to commit: once signing is excluded, the file is unchanged"
	exit 0
fi

git -C "$SUB" add "$REL"
git -C "$SUB" commit -m "$1"
echo "-- committed: $(git -C "$SUB" log --oneline -1)"
