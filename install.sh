#!/bin/sh

set -eu

repo="${SVW_REPOSITORY:-svcomplex-dev/svw}"
version="${SVW_VERSION:-latest}"
release_base_url="${SVW_RELEASE_BASE_URL:-https://github.com/${repo}/releases/download}"
user_home="${HOME:-}"
bin_dir="${SVW_BIN_DIR:-${user_home}/.local/bin}"
install_root="${SVW_INSTALL_ROOT:-${user_home}/.local/share/svw}"
modify_path=1

say() {
    printf '%s\n' "$*"
}

die() {
    printf 'svw installer: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Install svw from GitHub Releases.

Usage:
  install.sh [--version TAG] [--bin-dir DIR] [--install-root DIR]
             [--no-modify-path]

Environment variables:
  SVW_VERSION           Release tag to install (default: latest)
  SVW_BIN_DIR           Directory for the svw command (default: ~/.local/bin)
  SVW_INSTALL_ROOT      Package installation root (default: ~/.local/share/svw)
  SVW_NO_MODIFY_PATH    Set to 1 to leave shell startup files unchanged
  SVW_REPOSITORY        GitHub owner/repository (default: svcomplex-dev/svw)
  SVW_RELEASE_BASE_URL  Override the GitHub Release download base URL
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "$#" -ge 2 ] || die "--version requires a value"
            version=$2
            shift 2
            ;;
        --bin-dir)
            [ "$#" -ge 2 ] || die "--bin-dir requires a value"
            bin_dir=$2
            shift 2
            ;;
        --install-root)
            [ "$#" -ge 2 ] || die "--install-root requires a value"
            install_root=$2
            shift 2
            ;;
        --no-modify-path)
            modify_path=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

if [ "${SVW_NO_MODIFY_PATH:-0}" = "1" ]; then
    modify_path=0
fi

case "$version" in
    ''|*[!A-Za-z0-9._-]*)
        die "release tag may only contain letters, numbers, '.', '_' and '-'"
        ;;
esac

[ -n "$user_home" ] || die "HOME is not set"
[ -n "$bin_dir" ] || die "installation bin directory is empty"
[ -n "$install_root" ] || die "installation root is empty"

kernel=$(uname -s)
machine=$(uname -m)

case "$kernel:$machine" in
    Linux:x86_64|Linux:amd64)
        platform=linux-x64
        ;;
    Darwin:arm64|Darwin:aarch64)
        platform=macos-arm64
        ;;
    *)
        die "unsupported platform: $kernel $machine (supported: macOS arm64, Linux x64)"
        ;;
esac

asset="svw-${version}-${platform}.tar.gz"
archive_url="${release_base_url%/}/${version}/${asset}"
checksum_url="${archive_url}.sha256"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/svw-install.XXXXXX") || die "cannot create a temporary directory"
stage_dir=
backup_dir=

cleanup() {
    if [ -n "$stage_dir" ] && [ -e "$stage_dir" ]; then
        rm -rf "$stage_dir"
    fi
    if [ -n "$backup_dir" ] && [ -e "$backup_dir" ]; then
        rm -rf "$backup_dir"
    fi
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

download() {
    url=$1
    output=$2

    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
            --retry 3 --output "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --https-only --quiet --output-document="$output" "$url"
    else
        die "curl or wget is required"
    fi
}

archive="$tmp_dir/$asset"
checksum_file="${archive}.sha256"

say "Downloading svw ${version} for ${platform}..."
download "$archive_url" "$archive"
download "$checksum_url" "$checksum_file"

expected_sha=$(awk 'NR == 1 { print $1 }' "$checksum_file" | tr 'A-F' 'a-f')
case "$expected_sha" in
    *[!0-9a-f]*|'')
        die "invalid SHA-256 file: ${asset}.sha256"
        ;;
esac
[ "${#expected_sha}" -eq 64 ] || die "invalid SHA-256 file: ${asset}.sha256"

if command -v sha256sum >/dev/null 2>&1; then
    actual_sha=$(sha256sum "$archive" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then
    actual_sha=$(shasum -a 256 "$archive" | awk '{ print $1 }')
elif command -v openssl >/dev/null 2>&1; then
    actual_sha=$(openssl dgst -sha256 "$archive" | awk '{ print $NF }')
else
    die "sha256sum, shasum, or openssl is required to verify the download"
fi
actual_sha=$(printf '%s' "$actual_sha" | tr 'A-F' 'a-f')

[ "$actual_sha" = "$expected_sha" ] || die "SHA-256 verification failed for $asset"
say "Verified SHA-256: $actual_sha"

tar -tzf "$archive" >/dev/null 2>&1 || die "downloaded archive is not a valid gzip-compressed tar file"
if ! tar -tzf "$archive" | awk '
    /^\// { exit 1 }
    {
        count = split($0, component, "/")
        for (i = 1; i <= count; i++) {
            if (component[i] == "..") exit 1
        }
    }
'; then
    die "archive contains an unsafe path"
fi

extract_dir="$tmp_dir/extracted"
mkdir -p "$extract_dir"
tar -xzf "$archive" -C "$extract_dir"

binary_list="$tmp_dir/binaries"
find "$extract_dir" -type f -name svw -print > "$binary_list"
binary_count=$(wc -l < "$binary_list" | tr -d ' ')
[ "$binary_count" -eq 1 ] || die "release archive must contain exactly one file named 'svw'"
binary=$(sed -n '1p' "$binary_list")
chmod +x "$binary"
binary_relative=${binary#"$extract_dir"/}

mkdir -p "$install_root" "$bin_dir"
install_root=$(cd "$install_root" && pwd -P)
bin_dir=$(cd "$bin_dir" && pwd -P)

destination="$install_root/${version}-${platform}"
stage_dir="$install_root/.${version}-${platform}.new.$$"
backup_dir="$install_root/.${version}-${platform}.old.$$"

mv "$extract_dir" "$stage_dir"
if [ -e "$destination" ]; then
    mv "$destination" "$backup_dir"
fi
if ! mv "$stage_dir" "$destination"; then
    if [ -e "$backup_dir" ]; then
        mv "$backup_dir" "$destination"
    fi
    die "failed to install package into $destination"
fi
stage_dir=
if [ -e "$backup_dir" ]; then
    rm -rf "$backup_dir"
fi
backup_dir=

installed_binary="$destination/$binary_relative"
ln -sfn "$installed_binary" "$bin_dir/svw"

path_updated=0
case ":${PATH:-}:" in
    *:"$bin_dir":*)
        ;;
    *)
        if [ "$modify_path" -eq 1 ]; then
            case "${SHELL:-}" in
                */zsh) profile="$HOME/.zshrc" ;;
                */bash) profile="$HOME/.bashrc" ;;
                *) profile="$HOME/.profile" ;;
            esac

            marker="# Added by the svw installer"
            escaped_bin_dir=$(printf '%s' "$bin_dir" | sed "s/'/'\\\\''/g")
            path_line=$(printf "export PATH='%s':\"\$PATH\"" "$escaped_bin_dir")
            if ! grep -Fqx -e "$path_line" "$profile" >/dev/null 2>&1; then
                {
                    printf '\n%s\n' "$marker"
                    printf '%s\n' "$path_line"
                } >> "$profile"
                path_updated=1
            fi
        fi
        ;;
esac

say "Installed svw to $installed_binary"
say "Command link: $bin_dir/svw"
if [ "$path_updated" -eq 1 ]; then
    say "Updated $profile. Open a new terminal, or run:"
    say "  export PATH='$bin_dir':\"\$PATH\""
elif ! command -v svw >/dev/null 2>&1 && [ "$modify_path" -eq 0 ]; then
    say "Add $bin_dir to PATH to run svw without its full path."
fi
