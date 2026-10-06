#!/bin/bash
# Reads and writes Audio Balance's version, which lives in the project-level Debug and
# Release build settings of AudioBalance.xcodeproj/project.pbxproj. Every target
# inherits them, so the app and the embedded agent always ship the same version.
#
#   project-version.sh read  AudioBalance.xcodeproj/project.pbxproj
#   project-version.sh write AudioBalance.xcodeproj/project.pbxproj 1.2.0 57
#
# Each setting must appear exactly twice (Debug and Release); anything else means a
# target overrides it or the project no longer matches what this assumes, and
# writing would be a guess.

set -euo pipefail

die() {
  echo "project-version: $1" >&2
  exit 1
}

expected_count=2

setting_lines() {
  local pbxproj="$1" setting="$2"
  local count
  count="$(grep -cE "^[[:space:]]+$setting = [^;]*;$" "$pbxproj" || true)"
  ((count == expected_count)) || die "expected $expected_count $setting in $pbxproj, found $count"
}

read_version() {
  local pbxproj="$1"
  setting_lines "$pbxproj" MARKETING_VERSION

  local versions
  versions="$(sed -nE 's/^[[:space:]]+MARKETING_VERSION = ([^;]*);$/\1/p' "$pbxproj" | sort -u)"
  [[ "$(wc -l <<<"$versions" | tr -d ' ')" == 1 ]] ||
    die "MARKETING_VERSION differs between configurations in $pbxproj: $(tr '\n' ' ' <<<"$versions")"
  echo "$versions"
}

command="${1-}"
pbxproj="${2-}"

case "$command" in
  read | write)
    [[ -f "$pbxproj" ]] || die "project file not found: $pbxproj"
    ;;
  "") die "a command is required (read or write)" ;;
  *) die "unknown command '$command'" ;;
esac

case "$command" in
  read)
    read_version "$pbxproj"
    ;;

  write)
    marketing="${3-}"
    build="${4-}"
    [[ "$marketing" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
      die "marketing version must be X.Y.Z, got '$marketing'"
    [[ "$build" =~ ^[0-9]+$ ]] || die "build number must be a whole number, got '$build'"

    setting_lines "$pbxproj" MARKETING_VERSION
    setting_lines "$pbxproj" CURRENT_PROJECT_VERSION

    # Write to a temp file and move it into place only once it succeeds, so a
    # failure cannot leave a half-written project.
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT

    sed -E -e "s/^([[:space:]]+)MARKETING_VERSION = [^;]*;$/\1MARKETING_VERSION = $marketing;/" \
      -e "s/^([[:space:]]+)CURRENT_PROJECT_VERSION = [^;]*;$/\1CURRENT_PROJECT_VERSION = $build;/" \
      "$pbxproj" >"$tmp"

    # mktemp creates the file as 0600; keep the project's own permissions.
    chmod "$(stat -f %Lp "$pbxproj")" "$tmp"
    mv "$tmp" "$pbxproj"
    trap - EXIT

    echo "Set $pbxproj to $marketing ($build)"
    ;;
esac
