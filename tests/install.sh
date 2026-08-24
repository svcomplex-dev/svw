#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 code@svcomplex.ai

set -eu

project_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/svw-installer-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

release_dir="$test_dir/releases"
mock_bin="$test_dir/mock-bin"
brew_prefix="$test_dir/homebrew-prefix"
brew_log="$test_dir/brew.log"
brew_state="$test_dir/brew.state"
mkdir -p "$release_dir" "$mock_bin" "$brew_prefix/bin"

make_linux_asset() {
    release_tag=$1
    payload="$test_dir/payload-$release_tag"
    asset="svw-${release_tag}-linux-x64.tar.gz"
    mkdir -p "$payload/bin" "$payload/share/svw/agents"
    printf '#!/bin/sh\nprintf "%%s\\n" "linux-x64:%s"\n' "$release_tag" > "$payload/bin/svw"
    chmod +x "$payload/bin/svw"
    printf 'agent data\n' > "$payload/share/svw/agents/README.md"
    tar -czf "$release_dir/$asset" -C "$payload" .
    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$release_dir/$asset" | awk '{ print $1 }')
    else
        digest=$(shasum -a 256 "$release_dir/$asset" | awk '{ print $1 }')
    fi
    printf '%s  %s\n' "$digest" "$asset" > "$release_dir/$asset.sha256"
}

make_linux_asset latest
make_linux_asset release-0.1.0

cat > "$mock_bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
    -s) printf '%s\n' "$TEST_UNAME_S" ;;
    -m) printf '%s\n' "$TEST_UNAME_M" ;;
    *) exit 1 ;;
esac
EOF

cat > "$mock_bin/curl" <<'EOF'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            shift
            output=$1
            ;;
        https://*) url=$1 ;;
    esac
    shift
done
[ -n "$output" ] && [ -n "$url" ]
cp "$MOCK_RELEASE_DIR/${url##*/}" "$output"
EOF

cat > "$mock_bin/brew" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MOCK_BREW_LOG"
case "$1" in
    tap|trust|update) exit 0 ;;
    help)
        [ "${2:-}" = trust ] || exit 64
        [ "${MOCK_BREW_TRUST_SUPPORTED:-1}" = 1 ] || exit 64
        exit 0
        ;;
    list)
        formula=$3
        grep -Fqx "$formula" "$MOCK_BREW_STATE" 2>/dev/null
        ;;
    install|upgrade)
        formula=$2
        grep -Fqx "$formula" "$MOCK_BREW_STATE" 2>/dev/null ||
            printf '%s\n' "$formula" >> "$MOCK_BREW_STATE"
        mkdir -p "$MOCK_BREW_PREFIX/bin"
        cat > "$MOCK_BREW_PREFIX/bin/svw" <<'SCRIPT'
#!/bin/sh
case "${1:-}" in
    --version) printf '%s\n' 'svw 0.1.0 (Homebrew test)' ;;
    --help) printf '%s\n' 'svw help' ;;
    *) exit 64 ;;
esac
SCRIPT
        chmod +x "$MOCK_BREW_PREFIX/bin/svw"
        ;;
    link) exit 0 ;;
    --prefix)
        printf '%s\n' "$MOCK_BREW_PREFIX"
        ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$mock_bin/uname" "$mock_bin/curl" "$mock_bin/brew"

run_linux_install() {
    requested=$1
    release_tag=$2
    if [ "$requested" = default ]; then
        set --
    else
        set -- --version "$requested"
    fi
    home_dir="$test_dir/home-linux-$release_tag"
    mkdir -p "$home_dir"
    HOME="$home_dir" \
    SHELL=/bin/zsh \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Linux \
    TEST_UNAME_M=x86_64 \
    MOCK_RELEASE_DIR="$release_dir" \
    SVW_RELEASE_BASE_URL=https://example.invalid/releases/download \
        sh "$project_dir/install.sh" "$@"

    result=$("$home_dir/.local/bin/svw")
    [ "$result" = "linux-x64:$release_tag" ]
    [ -L "$home_dir/.local/bin/svw" ]
    [ -f "$home_dir/.local/share/svw/$release_tag-linux-x64/share/svw/agents/README.md" ]
    grep -F '# Added by the svw installer' "$home_dir/.zshrc" >/dev/null

    HOME="$home_dir" \
    SHELL=/bin/zsh \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Linux \
    TEST_UNAME_M=x86_64 \
    MOCK_RELEASE_DIR="$release_dir" \
    SVW_RELEASE_BASE_URL=https://example.invalid/releases/download \
        sh "$project_dir/install.sh" "$@" >/dev/null
    [ "$(grep -c '# Added by the svw installer' "$home_dir/.zshrc")" -eq 1 ]
}

run_linux_install default release-0.1.0
run_linux_install latest latest
run_linux_install 0.1.0 release-0.1.0
run_linux_install release-0.1.0 release-0.1.0

run_macos_install() {
    requested=$1
    expected_formula=$2
    if [ "$requested" = default ]; then
        set --
    else
        set -- --version "$requested"
    fi
    home_dir="$test_dir/home-macos"
    mkdir -p "$home_dir"
    HOME="$home_dir" \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Darwin \
    TEST_UNAME_M=arm64 \
    MOCK_BREW_LOG="$brew_log" \
    MOCK_BREW_STATE="$brew_state" \
    MOCK_BREW_PREFIX="$brew_prefix" \
        sh "$project_dir/install.sh" "$@"
    grep -Fqx "tap svcomplex-dev/tap" "$brew_log"
    grep -Fqx "help trust" "$brew_log"
    grep -Fqx "trust svcomplex-dev/tap" "$brew_log"
    grep -Fqx "install $expected_formula" "$brew_log"
}

run_macos_install default svcomplex-dev/tap/svw
run_macos_install latest svcomplex-dev/tap/svw-latest
run_macos_install 0.1.0 svcomplex-dev/tap/svw@0.1.0
grep -Fqx "link --overwrite --force svcomplex-dev/tap/svw-latest" "$brew_log"
grep -Fqx "link --overwrite --force svcomplex-dev/tap/svw@0.1.0" "$brew_log"

no_trust_home="$test_dir/home-macos-no-trust"
no_trust_log="$test_dir/brew-no-trust.log"
no_trust_state="$test_dir/brew-no-trust.state"
no_trust_prefix="$test_dir/homebrew-no-trust-prefix"
mkdir -p "$no_trust_home" "$no_trust_prefix/bin"
HOME="$no_trust_home" \
PATH="$mock_bin:/usr/bin:/bin" \
TEST_UNAME_S=Darwin \
TEST_UNAME_M=arm64 \
MOCK_BREW_LOG="$no_trust_log" \
MOCK_BREW_STATE="$no_trust_state" \
MOCK_BREW_PREFIX="$no_trust_prefix" \
MOCK_BREW_TRUST_SUPPORTED=0 \
    sh "$project_dir/install.sh"
grep -Fqx "tap svcomplex-dev/tap" "$no_trust_log"
grep -Fqx "help trust" "$no_trust_log"
if grep -Fqx "trust svcomplex-dev/tap" "$no_trust_log"; then
    printf 'unsupported brew trust must not be invoked\n' >&2
    exit 1
fi
grep -Fqx "install svcomplex-dev/tap/svw" "$no_trust_log"

bad_home="$test_dir/home-bad-hash"
mkdir -p "$bad_home" "$test_dir/bad-release"
cp "$release_dir/svw-release-0.1.0-linux-x64.tar.gz" "$test_dir/bad-release/"
printf '%064d  svw-release-0.1.0-linux-x64.tar.gz\n' 0 \
    > "$test_dir/bad-release/svw-release-0.1.0-linux-x64.tar.gz.sha256"
if HOME="$bad_home" \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Linux \
    TEST_UNAME_M=x86_64 \
    MOCK_RELEASE_DIR="$test_dir/bad-release" \
    SVW_RELEASE_BASE_URL=https://example.invalid/releases/download \
        sh "$project_dir/install.sh" >/dev/null 2>&1; then
    printf 'expected a bad checksum to fail\n' >&2
    exit 1
fi
[ ! -e "$bad_home/.local/bin/svw" ]

if HOME="$test_dir/home-unsupported" \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Linux \
    TEST_UNAME_M=aarch64 \
        sh "$project_dir/install.sh" >/dev/null 2>&1; then
    printf 'expected an unsupported platform to fail\n' >&2
    exit 1
fi

if HOME="$test_dir/home-macos-layout" \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Darwin \
    TEST_UNAME_M=arm64 \
    MOCK_BREW_LOG="$brew_log" \
    MOCK_BREW_STATE="$brew_state" \
    MOCK_BREW_PREFIX="$brew_prefix" \
        sh "$project_dir/install.sh" --bin-dir "$test_dir/bin" >/dev/null 2>&1; then
    printf 'expected a custom macOS layout to fail\n' >&2
    exit 1
fi

for invalid in 0.1 release-01.2.3 release-1.2.3-rc1 latest/main; do
    if HOME="$test_dir/home-invalid" \
        PATH="$mock_bin:/usr/bin:/bin" \
        TEST_UNAME_S=Linux \
        TEST_UNAME_M=x86_64 \
            sh "$project_dir/install.sh" --version "$invalid" >/dev/null 2>&1; then
        printf 'expected invalid version %s to fail\n' "$invalid" >&2
        exit 1
    fi
done

printf 'installer tests passed\n'
