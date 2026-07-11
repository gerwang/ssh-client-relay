#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    local expected="$1" file="$2"
    local actual
    actual="$(cat "$file")"
    [[ "$actual" == "$expected" ]] || fail "$file: expected [$expected], got [$actual]"
}

chmod +x "$repo/tests/fake-ssh.sh" "$repo/tests/fake-sshfs.sh"
mkdir -p "$work/home/.config/ssh-client-relay" "$work/fake-bin"
cat >"$work/home/.config/ssh-client-relay/config" <<EOF
SSH=$repo/tests/fake-ssh.sh
RELAY_HOST=relay.example
TARGET_ALIAS=compute
TARGET_HOST=compute.example.org
REMOTE_HELPER=~/.local/bin/ssh-client-relay-helper
EOF

export HOME="$work/home"
export TEST_ARGS="$work/args"
export TEST_STDIN="$work/stdin"

assert_file 'ssh-client-relay 0.1.0' <("$repo/bin/ssh-client-relay" --version)

output="$(printf payload | "$repo/bin/ssh-client-relay" other 'arg with space')"
[[ "$output" == fake-ssh-output ]] || fail 'direct output was not relayed'
assert_file $'other\narg with space' "$TEST_ARGS"
assert_file payload "$TEST_STDIN"

printf payload | "$repo/bin/ssh-client-relay" -T -D 1080 compute 'printf hello' >/dev/null
assert_file $'-x\n-T\n-L\n1080:127.0.0.1:1080\nrelay.example\n'"$HOME/.local/bin/ssh-client-relay-helper" "$TEST_ARGS"
perl -0 -e '
    use strict; use warnings;
    my $file = shift;
    open my $fh, "<", $file or die $!;
    local $/; my $data = <$fh>;
    my @expected = ("SSH_CLIENT_RELAY_ARGS_V1", "5", "-T", "-D", "1080",
                    "compute.example.org", "printf hello");
    for my $expected (@expected) {
        $data =~ s/^([^\0]*)\0// or die "missing framed field\n";
        die "expected [$expected], got [$1]\n" unless $1 eq $expected;
    }
    die "payload mismatch\n" unless $data eq "payload";
' "$TEST_STDIN"

printf x | "$repo/bin/ssh-client-relay" -D1081 compute true >/dev/null
grep -qx '1081:127.0.0.1:1081' "$TEST_ARGS" || fail 'attached -D was not bridged'

printf 'SSH_CLIENT_RELAY_ARGS_V1\0' >"$work/helper-input"
printf '1\0-V\0' >>"$work/helper-input"
"$repo/libexec/ssh-client-relay-helper" <"$work/helper-input" 2>&1 |
    grep -q OpenSSH || fail 'helper did not execute framed ssh -V'
printf '\xEF\xBB\xBFSSH_CLIENT_RELAY_ARGS_V1\0' >"$work/helper-input"
printf '1\0-V\0' >>"$work/helper-input"
"$repo/libexec/ssh-client-relay-helper" <"$work/helper-input" 2>&1 |
    grep -q OpenSSH || fail 'helper did not accept UTF-8 BOM'

ln -s "$repo/tests/fake-sshfs.sh" "$work/fake-bin/sshfs"
PATH="$work/fake-bin:$PATH" SSH_CLIENT_RELAY_BIN="$repo/bin/ssh-client-relay" \
    "$repo/bin/ssh-client-relay-sshfs" -f compute:/data "$work/mount"
assert_file $'-o\nssh_command='"$repo"$'/bin/ssh-client-relay\n-f\ncompute:/data\n'"$work/mount" "$TEST_ARGS"

printf 'Linux tests passed\n'
