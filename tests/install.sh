#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/svw-installer-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

release_dir="$test_dir/releases"
mock_bin="$test_dir/mock-bin"
mkdir -p "$release_dir" "$mock_bin"

make_asset() {
    platform=$1
    payload="$test_dir/payload-$platform"
    asset="svw-latest-$platform.tar.gz"

    mkdir -p "$payload/package/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$platform" > "$payload/package/bin/svw"
    chmod +x "$payload/package/bin/svw"
    printf 'test license\n' > "$payload/package/LICENSE"
    tar -czf "$release_dir/$asset" -C "$payload" package
    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$release_dir/$asset" | awk '{ print $1 }')
    else
        digest=$(shasum -a 256 "$release_dir/$asset" | awk '{ print $1 }')
    fi
    printf '%s  %s\n' "$digest" "$asset" > "$release_dir/$asset.sha256"
}

make_asset linux-x64
make_asset macos-arm64

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
        https://*)
            url=$1
            ;;
    esac
    shift
done
[ -n "$output" ] && [ -n "$url" ]
cp "$MOCK_RELEASE_DIR/${url##*/}" "$output"
EOF
chmod +x "$mock_bin/uname" "$mock_bin/curl"

run_install_test() {
    kernel=$1
    machine=$2
    expected_platform=$3
    home_dir="$test_dir/home-$expected_platform"
    mkdir -p "$home_dir"

    HOME="$home_dir" \
    SHELL=/bin/zsh \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S="$kernel" \
    TEST_UNAME_M="$machine" \
    MOCK_RELEASE_DIR="$release_dir" \
    SVW_RELEASE_BASE_URL=https://example.invalid/releases/download \
        sh "$project_dir/install.sh"

    result=$("$home_dir/.local/bin/svw")
    [ "$result" = "$expected_platform" ]
    [ -L "$home_dir/.local/bin/svw" ]
    [ -f "$home_dir/.local/share/svw/latest-$expected_platform/package/LICENSE" ]
    grep -F '# Added by the svw installer' "$home_dir/.zshrc" >/dev/null

    # A second installation must be idempotent, including the PATH entry.
    HOME="$home_dir" \
    SHELL=/bin/zsh \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S="$kernel" \
    TEST_UNAME_M="$machine" \
    MOCK_RELEASE_DIR="$release_dir" \
    SVW_RELEASE_BASE_URL=https://example.invalid/releases/download \
        sh "$project_dir/install.sh" >/dev/null
    marker_count=$(grep -c '# Added by the svw installer' "$home_dir/.zshrc")
    [ "$marker_count" -eq 1 ]
}

run_install_test Linux x86_64 linux-x64
run_install_test Darwin arm64 macos-arm64

bad_home="$test_dir/home-bad-hash"
mkdir -p "$bad_home" "$test_dir/bad-release"
cp "$release_dir/svw-latest-linux-x64.tar.gz" "$test_dir/bad-release/"
printf '%064d  svw-latest-linux-x64.tar.gz\n' 0 \
    > "$test_dir/bad-release/svw-latest-linux-x64.tar.gz.sha256"

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

unsupported_home="$test_dir/home-unsupported"
mkdir -p "$unsupported_home"
if HOME="$unsupported_home" \
    PATH="$mock_bin:/usr/bin:/bin" \
    TEST_UNAME_S=Linux \
    TEST_UNAME_M=aarch64 \
        sh "$project_dir/install.sh" >/dev/null 2>&1; then
    printf 'expected an unsupported platform to fail\n' >&2
    exit 1
fi

printf 'installer tests passed\n'

