#!/bin/sh
#
# pack.sh - pack NotWorthIt into a versioned distribution tarball.
#
# Stages the addon payload into a single NotWorthIt/ wrapper folder (the
# installed layout) and tars it to dist/NotWorthIt-<version>.tar.gz, ready
# to upload to CurseForge or a GitHub release, or to extract straight into
# Interface/AddOns/ for an instant install.
#
# The version comes from the '## Version:' line of NotWorthIt.toc and the
# run fails loudly when it is missing or malformed. Staging happens in a
# mktemp directory removed on every exit path, and only the payload items
# are packaged: repo tooling, including this script, stays out of the
# archive.
#
# POSIX sh (no bashisms); verified under Git for Windows sh. On Git for
# Windows, pass -o an MSYS-style path (/c/...) - native tar rejects drive
# paths like C:\ as host specifications.

set -eu

# Named constants - keep in sync with pack.ps1 (Portability contract).
ADDON_NAME=NotWorthIt
# shellcheck disable=SC2086  # word-splitting is how the list is iterated
PAYLOAD_ITEMS='NotWorthIt.lua NotWorthIt.toc README.md CHANGELOG.md'
DEFAULT_OUTPUT_SUBDIR=dist

usage() {
    cat <<'EOF'
pack.sh - pack NotWorthIt into a versioned distribution tarball.

Usage:
  ./pack.sh                Pack into dist/NotWorthIt-<version>.tar.gz
  ./pack.sh -o <dir>       Pack into <dir>/NotWorthIt-<version>.tar.gz
  ./pack.sh -h             Show this help
EOF
}

# The script lives at the repository root, so its directory is the repo root.
repo_root=$(CDPATH= cd "$(dirname "$0")" && pwd -P)

# Payload validation: fail with the full missing list before any output.
missing=''
for item in $PAYLOAD_ITEMS; do
    if [ ! -f "$repo_root/$item" ]; then
        missing="$missing $item"
    fi
done
if [ -n "$missing" ]; then
    printf '%s\n' "pack.sh: missing payload item(s) in $repo_root:$missing" >&2
    printf '%s\n' "The archive needs every payload item listed in PAYLOAD_ITEMS. Restore" >&2
    printf '%s\n' "or regenerate them, or update the list here and in pack.ps1." >&2
    exit 1
fi

# Version source: the '## Version:' line of the .toc.
toc="$repo_root/$ADDON_NAME.toc"
version=$(sed -n 's/^##[[:space:]]*Version:[[:space:]]*//p' "$toc" \
    | head -n 1 | tr -d '\r' | sed 's/[[:space:]]*$//')
case $version in
    '' | *[!0-9A-Za-z.-]*)
        printf '%s\n' "pack.sh: no usable '## Version:' line in $toc (got '$version')." >&2
        exit 1
        ;;
esac

# Destination: -o wins, else dist/ under the repo root.
output_dir="$repo_root/$DEFAULT_OUTPUT_SUBDIR"
while [ $# -gt 0 ]; do
    case $1 in
        -o)
            if [ $# -lt 2 ]; then
                printf '%s\n' 'pack.sh: -o requires a directory argument.' >&2
                exit 2
            fi
            output_dir=$2
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "pack.sh: unknown argument '$1' (see ./pack.sh -h)." >&2
            exit 2
            ;;
    esac
done

# mktemp -d staging tree; the trap is set immediately so no exit path
# (including a set -e abort) leaks it.
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/notworthit-pack-XXXXXXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM

staged_folder="$staging_dir/$ADDON_NAME"
mkdir -p "$staged_folder"
for item in $PAYLOAD_ITEMS; do
    cp -p "$repo_root/$item" "$staged_folder/"
done
staged_files=$(find "$staged_folder" -type f | wc -l | tr -d ' ')

mkdir -p "$output_dir"
archive_path="$output_dir/$ADDON_NAME-$version.tar.gz"
tar -czf "$archive_path" -C "$staging_dir" "$ADDON_NAME"
tar -tzf "$archive_path" > /dev/null

archive_bytes=$(wc -c < "$archive_path" | tr -d ' ')
archive_kb=$(( (archive_bytes + 1023) / 1024 ))

printf '%s\n' "Packed $ADDON_NAME $version ($staged_files files) -> $archive_path (${archive_kb} KB)"
printf '%s\n' 'Recipient paths:'
printf '%s\n' '  - Upload the tarball to CurseForge or attach it to a GitHub release.'
printf '%s\n' '  - Or extract it into Interface/AddOns/ for an instant install.'
