#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

relay_host="${RELAY_HOST:-${1:-}}"
target_alias="${TARGET_ALIAS:-${2:-}}"
target_host="${TARGET_HOST:-${3:-}}"
local_bin="${LOCAL_BIN:-$HOME/.local/bin}"
config_dir="${CONFIG_DIR:-$HOME/.config/ssh-client-relay}"
remote_helper="${REMOTE_HELPER:-.local/bin/ssh-client-relay-helper}"
remote_tmp="${remote_helper}.new.$$.${RANDOM}"

valid_remote_path() {
    local path="$1" part LC_ALL=C
    local -a parts
    [[ -n "$path" && "$path" != /* && "$path" != */ && "$path" != *//* ]] ||
        return 1
    [[ "$path" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    IFS=/ read -r -a parts <<<"$path"
    for part in "${parts[@]}"; do
        [[ "$part" != . && "$part" != .. ]] || return 1
    done
}

if [[ -z "$relay_host" || -z "$target_alias" || -z "$target_host" ]]; then
    printf 'Usage: %s RELAY_HOST TARGET_ALIAS TARGET_HOST\n' "$0" >&2
    printf 'The same values may be set as environment variables.\n' >&2
    exit 64
fi

if ! valid_remote_path "$remote_helper"; then
    printf 'REMOTE_HELPER must be a safe path relative to the relay home: %s\n' \
        "$remote_helper" >&2
    exit 64
fi

remote_dir="${remote_helper%/*}"
[[ "$remote_dir" != "$remote_helper" ]] || remote_dir=.

for command in ssh scp install; do
    command -v "$command" >/dev/null || {
        printf 'Missing required command: %s\n' "$command" >&2
        exit 69
    }
done

install -d -m 700 "$local_bin" "$config_dir"
install -m 700 "$script_dir/bin/ssh-client-relay" "$local_bin/ssh-client-relay"
install -m 700 "$script_dir/bin/ssh-client-relay-sshfs" \
    "$local_bin/ssh-client-relay-sshfs"

config_tmp="$config_dir/config.new.$$"
trap 'rm -f "$config_tmp"' EXIT
{
    printf 'RELAY_HOST=%q\n' "$relay_host"
    printf 'TARGET_ALIAS=%q\n' "$target_alias"
    printf 'TARGET_HOST=%q\n' "$target_host"
    printf 'REMOTE_HELPER=%q\n' "~/$remote_helper"
} >"$config_tmp"
chmod 600 "$config_tmp"
mv -f "$config_tmp" "$config_dir/config"

ssh -x -T "$relay_host" \
    "mkdir -p ~/$remote_dir && chmod 700 ~/$remote_dir"
scp -q "$script_dir/libexec/ssh-client-relay-helper" "$relay_host:$remote_tmp"
ssh -x -T "$relay_host" \
    "chmod 700 ~/$remote_tmp && mv -f ~/$remote_tmp ~/$remote_helper"

printf 'Installed local wrapper: %s/ssh-client-relay\n' "$local_bin"
printf 'Installed SSHFS wrapper: %s/ssh-client-relay-sshfs\n' "$local_bin"
printf 'Installed remote helper: %s:~/%s\n' "$relay_host" "$remote_helper"
printf 'Dispatch route: %s -> %s -> %s\n' \
    "$target_alias" "$relay_host" "$target_host"
