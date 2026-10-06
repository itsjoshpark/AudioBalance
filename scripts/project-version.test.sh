#!/bin/bash
# Tests for project-version.sh. Run directly: ./scripts/project-version.test.sh

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="$script_dir/project-version.sh"

failures=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

check() {
  if [[ "$2" == "pass" ]]; then
    echo "ok       $1"
  else
    echo "FAIL     $1"
    failures=$((failures + 1))
  fi
}

expect_equal() {
  local got="$1" want="$2" description="$3"
  if [[ "$got" == "$want" ]]; then
    check "$description" pass
  else
    check "$description (got '$got', want '$want')" fail
  fi
}

expect_failure() {
  local description="$1"
  shift
  if "$tool" "$@" >/dev/null 2>&1; then
    check "$description" fail
  else
    check "$description" pass
  fi
}

# Mirrors the real project: the version in the project-level Debug and Release settings.
make_fixture() {
  cat >"$workdir/project.pbxproj" <<'PBX'
		AB00000000000000000000A0 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = 1.4.0;
				CURRENT_PROJECT_VERSION = 12;
				SDKROOT = macosx;
			};
			name = Debug;
		};
		AB00000000000000000000A1 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = 1.4.0;
				CURRENT_PROJECT_VERSION = 12;
				SDKROOT = macosx;
			};
			name = Release;
		};
PBX
}

pbx="$workdir/project.pbxproj"
make_fixture

# --- read -------------------------------------------------------------------
expect_equal "$("$tool" read "$pbx")" "1.4.0" "reads the marketing version"

# --- write ------------------------------------------------------------------
cp "$pbx" "$workdir/original.pbxproj"
if "$tool" write "$pbx" 1.5.0 40 >/dev/null 2>&1; then
  check "exits zero on write" pass
else
  check "exits zero on write" fail
fi
expect_equal "$("$tool" read "$pbx")" "1.5.0" "writes the marketing version"
expect_equal "$(grep -c $'^\t\t\t\tMARKETING_VERSION = 1.5.0;$' "$pbx")" "2" "updates both MARKETING_VERSION lines, keeping indentation"
expect_equal "$(grep -c $'^\t\t\t\tCURRENT_PROJECT_VERSION = 40;$' "$pbx")" "2" "updates both CURRENT_PROJECT_VERSION lines, keeping indentation"
expect_equal "$(diff "$workdir/original.pbxproj" "$pbx" | grep -c '^>')" "4" "changes only the four version lines"
expect_equal "$(stat -f %Lp "$pbx")" "$(stat -f %Lp "$workdir/original.pbxproj")" "keeps the file's permissions"

# --- guards -----------------------------------------------------------------
make_fixture
expect_failure "rejects a missing project file" read "$workdir/nope.pbxproj"
expect_failure "rejects a missing command" ""
expect_failure "rejects an unknown command" bump "$pbx"

# Debug and Release must agree, or a release would read an arbitrary one.
make_fixture
awk '!done && /MARKETING_VERSION = 1.4.0;/ { sub(/1\.4\.0/, "1.3.0"); done = 1 } 1' "$pbx" >"$workdir/tmp" && mv "$workdir/tmp" "$pbx"
expect_failure "rejects configurations with different versions" read "$pbx"

# A target-level override would be left behind by a write.
make_fixture
printf '\t\t\t\tMARKETING_VERSION = 1.4.0;\n' >>"$pbx"
expect_failure "rejects a third MARKETING_VERSION" read "$pbx"
expect_failure "refuses to write when MARKETING_VERSION appears three times" write "$pbx" 1.5.0 40

make_fixture
grep -v CURRENT_PROJECT_VERSION "$pbx" >"$workdir/tmp" && mv "$workdir/tmp" "$pbx"
expect_failure "refuses to write without CURRENT_PROJECT_VERSION" write "$pbx" 1.5.0 40

make_fixture
for bad in "" "1.5" "1.5.0;" "1.5.0 extra" "01.5.0"; do
  expect_failure "rejects marketing version '$bad'" write "$pbx" "$bad" 40
done
for bad in "" "abc" "4.0" "-1"; do
  expect_failure "rejects build number '$bad'" write "$pbx" 1.5.0 "$bad"
done
expect_equal "$("$tool" read "$pbx")" "1.4.0" "leaves the file untouched when validation fails"

# The real project, which is what a release reads.
if "$tool" read "$script_dir/../AudioBalance.xcodeproj/project.pbxproj" >/dev/null 2>&1; then
  check "reads the real project" pass
else
  check "reads the real project" fail
fi

echo
if ((failures > 0)); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
