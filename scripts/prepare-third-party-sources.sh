#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="$PROJECT_DIR/build/third-party-sources-v0.2.0"
ARCHIVE="$PROJECT_DIR/build/StickS3-Virtual-Device-v0.2.0-third-party-sources.zip"
QEMU_TAG="esp-develop-9.2.2-20250817"
QEMU_COMMIT="4f4148e2f68689eb8861bf9fce0b46ada9200fef"
QEMU_SHA256="a742e58d930fe2d6a9ad408fe5971baaae8f3a310f3f3952324c13258a59f503"
QEMU_LOCAL_SOURCE="${QEMU_SOURCE_ARCHIVE:-$HOME/Downloads/$QEMU_TAG.tar.gz}"

mkdir -p "$OUTPUT_DIR"

download() {
    local filename="$1"
    local url="$2"
    local checksum="$3"
    local destination="$OUTPUT_DIR/$filename"
    local downloads_copy="$HOME/Downloads/$filename"

    if [[ -f "$destination" && -n "$checksum" ]]; then
        local existing
        existing="$(shasum -a 256 "$destination" | awk '{print $1}')"
        [[ "$existing" == "$checksum" ]] && return 0
    fi

    if [[ -f "$downloads_copy" && -n "$checksum" ]]; then
        local downloaded
        downloaded="$(shasum -a 256 "$downloads_copy" | awk '{print $1}')"
        if [[ "$downloaded" == "$checksum" ]]; then
            cp "$downloads_copy" "$destination"
            return 0
        fi
    fi

    curl --fail --location --retry 5 --continue-at - --output "$destination" "$url"
    if [[ -n "$checksum" ]]; then
        local actual
        actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
        [[ "$actual" == "$checksum" ]] || {
            print -u2 -- "SHA-256 mismatch for $filename"
            exit 65
        }
    fi
}

remote_commit="$(git ls-remote "https://github.com/espressif/qemu.git" "refs/tags/$QEMU_TAG^{}" | awk '{print $1}')"
[[ "$remote_commit" == "$QEMU_COMMIT" ]] || {
    print -u2 -- "QEMU tag commit does not match the reviewed release"
    exit 65
}

if [[ -f "$QEMU_LOCAL_SOURCE" ]]; then
    cp "$QEMU_LOCAL_SOURCE" "$OUTPUT_DIR/qemu-$QEMU_TAG.tar.gz"
    actual_qemu="$(shasum -a 256 "$OUTPUT_DIR/qemu-$QEMU_TAG.tar.gz" | awk '{print $1}')"
    [[ "$actual_qemu" == "$QEMU_SHA256" ]] || {
        print -u2 -- "SHA-256 mismatch for the local QEMU source archive"
        exit 65
    }
else
    download "qemu-$QEMU_TAG.tar.gz" \
        "https://github.com/espressif/qemu/archive/refs/tags/$QEMU_TAG.tar.gz" \
        "$QEMU_SHA256"
fi
download "gettext-1.0.tar.gz" \
    "https://ftpmirror.gnu.org/gnu/gettext/gettext-1.0.tar.gz" \
    "85d99b79c981a404874c02e0342176cf75c7698e2b51fe41031cf6526d974f1a"
download "glib-2.88.3.tar.xz" \
    "https://download.gnome.org/sources/glib/2.88/glib-2.88.3.tar.xz" \
    "ab24d24e698dfa1e408b7bcdb508f4aafc906185a8b8ce72fdf79bbbdc9b383b"
download "libgcrypt-1.12.2.tar.bz2" \
    "https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.12.2.tar.bz2" \
    "7ce33c2492221a0436f96a8500215e9f3e3dcb5fd26a757cd415e7a843babd5e"
download "libgpg-error-1.61.tar.bz2" \
    "https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.61.tar.bz2" \
    "7a85413f2bc354f4f8aa832b718af122e48965e9e0eb9012ee659c13c6385c93"
download "pcre2-10.47.tar.bz2" \
    "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.bz2" \
    "47fe8c99461250d42f89e6e8fdaeba9da057855d06eb7fc08d9ca03fd08d7bc7"
download "pixman-0.46.4.tar.gz" \
    "https://cairographics.org/releases/pixman-0.46.4.tar.gz" \
    "d09c44ebc3bd5bee7021c79f922fe8fb2fb57f7320f55e97ff9914d2346a591c"
download "sdl2-compat-2.32.70.tar.gz" \
    "https://github.com/libsdl-org/sdl2-compat/releases/download/release-2.32.70/sdl2-compat-2.32.70.tar.gz" \
    "998fa62557eb46ffe7e5c3e2c123bc332f7df9d9f593b3ceed88ed1158428a44"

cp "$PROJECT_DIR/docs/THIRD_PARTY_SOURCE_DISTRIBUTION.md" "$OUTPUT_DIR/README.md"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 ./* > SHA256SUMS.txt
)
rm -f "$ARCHIVE"
(
    cd "$OUTPUT_DIR:h"
    ditto -c -k --keepParent "$OUTPUT_DIR:t" "$ARCHIVE"
)
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
print -r -- "$ARCHIVE"
