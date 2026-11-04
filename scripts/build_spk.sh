#!/bin/bash
#
# build_spk.sh - Build Synology DSM 7.2+ SPK package for Jellyfin
#
# Usage:
#   ./build_spk.sh <version> [arch]
#
#   version  - Jellyfin version (e.g. 12.4)
#   arch     - Target architecture: amd64 (default) or arm64
#

set -euo pipefail

# ── Arguments ──────────────────────────────────────────────────────────────────
JELLYFIN_VERSION="${1:?Usage: build_spk.sh <version> [arch]}"
ARCH="${2:-amd64}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="${PROJECT_DIR}/templates"
AUX_DIR="${PROJECT_DIR}/aux"
WORK_DIR="${PROJECT_DIR}/build"
OUTPUT_DIR="${PROJECT_DIR}/output"

# Jellyfin binary download URLs
JELLYFIN_REPO="https://repo.jellyfin.org/files/server/linux/stable/v${JELLYFIN_VERSION}"

# Map arch to Jellyfin download arch and SPK arch
case "$ARCH" in
    amd64)
        JELLYFIN_ARCH="amd64"
        SPK_ARCH="x64"
        ;;
    arm64)
        JELLYFIN_ARCH="arm64"
        SPK_ARCH="arm64v8"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH (use amd64 or arm64)"
        exit 1
        ;;
esac

echo "════════════════════════════════════════════════════════════════"
echo "  Building Jellyfin ${JELLYFIN_VERSION} SPK for ${ARCH} (${SPK_ARCH})"
echo "════════════════════════════════════════════════════════════════"

# ── Clean and create work directories ──────────────────────────────────────────
rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# ── Step 1: Download Jellyfin binary ───────────────────────────────────────────
echo ""
echo "[1/6] Downloading Jellyfin ${JELLYFIN_VERSION} (${ARCH})..."

JELLYFIN_TGZ="${WORK_DIR}/jellyfin_${JELLYFIN_VERSION}-${JELLYFIN_ARCH}.tar.gz"
JELLYFIN_URL="${JELLYFIN_REPO}/${JELLYFIN_ARCH}/jellyfin_${JELLYFIN_VERSION}-${JELLYFIN_ARCH}.tar.gz"

echo "  URL: ${JELLYFIN_URL}"
curl -fSL -o "$JELLYFIN_TGZ" "$JELLYFIN_URL"
echo "  Downloaded: $(du -h "$JELLYFIN_TGZ" | cut -f1)"

# Extract
JELLYFIN_EXTRACT="${WORK_DIR}/jellyfin"
mkdir -p "$JELLYFIN_EXTRACT"
tar -xzf "$JELLYFIN_TGZ" -C "$JELLYFIN_EXTRACT"
echo "  Extracted to: ${JELLYFIN_EXTRACT}"

# Find the actual jellyfin directory (may be nested)
JELLYFIN_BIN_DIR=$(find "$JELLYFIN_EXTRACT" -name "jellyfin" -type f -exec dirname {} \; | head -1)
if [ -z "$JELLYFIN_BIN_DIR" ]; then
    echo "ERROR: Could not find jellyfin binary in extracted archive"
    exit 1
fi
echo "  Binary dir: ${JELLYFIN_BIN_DIR}"

# ── Step 2: Extract auxiliary files from local repo ────────────────────────────
echo ""
echo "[2/6] Extracting auxiliary files from local repo (aux/)..."

REF_PKG_EXTRACT="${WORK_DIR}/ref_pkg"
mkdir -p "$REF_PKG_EXTRACT"

# Reassemble split xz archive and extract
cat "${AUX_DIR}/jellyfin-aux-files.tar.xz.partaa" \
    "${AUX_DIR}/jellyfin-aux-files.tar.xz.partab" \
    "${AUX_DIR}/jellyfin-aux-files.tar.xz.partac" \
    | xz -d | tar -xf - -C "$REF_PKG_EXTRACT"

echo "  Auxiliary files extracted: $(du -sh "$REF_PKG_EXTRACT" | cut -f1)"

# ── Step 3: Assemble package.tgz contents ──────────────────────────────────────
echo ""
echo "[3/6] Assembling package contents..."

PKG_DIR="${WORK_DIR}/package"
mkdir -p "$PKG_DIR"

# Copy all non-service directories from auxiliary files (bin, cache, config, data, etc, include, lib, logs, share, ui)
for dir in bin cache config data etc include lib logs share ui; do
    if [ -d "${REF_PKG_EXTRACT}/${dir}" ]; then
        cp -a "${REF_PKG_EXTRACT}/${dir}" "${PKG_DIR}/"
    fi
done

# Create service directory with new Jellyfin binary
mkdir -p "${PKG_DIR}/service"

# Copy new Jellyfin binary (includes DLLs, .so, jellyfin-web, etc.)
cp -a "$JELLYFIN_BIN_DIR" "${PKG_DIR}/service/bin"

# Move web UI from service/bin/jellyfin-web to service/web
WEB_DIR="${PKG_DIR}/service/bin/jellyfin-web"
if [ -d "$WEB_DIR" ]; then
    mv "$WEB_DIR" "${PKG_DIR}/service/web"
    echo "  Web UI moved to service/web ($(find ${PKG_DIR}/service/web -type f | wc -l) files)"
else
    echo "  WARNING: Web UI directory not found, Jellyfin will use embedded web files"
fi

# Ensure required directories exist
mkdir -p "${PKG_DIR}/logs"
mkdir -p "${PKG_DIR}/cache"

echo "  Package contents assembled: $(du -sh "$PKG_DIR" | cut -f1)"

# ── Step 4: Create package.tgz ─────────────────────────────────────────────────
echo ""
echo "[4/6] Creating package.tgz..."

cd "$PKG_DIR"
tar -czf "${WORK_DIR}/package.tgz" \
    bin cache config data etc include lib logs service share ui
cd - > /dev/null

PKG_SIZE=$(stat -c %s "${WORK_DIR}/package.tgz")
echo "  package.tgz: $(du -h "${WORK_DIR}/package.tgz" | cut -f1) (${PKG_SIZE} bytes)"

# Calculate MD5 checksum (Synology uses MD5 of the compressed package.tgz)
CHECKSUM=$(md5sum "${WORK_DIR}/package.tgz" | awk '{print $1}')
echo "  Checksum: ${CHECKSUM}"

# ── Step 5: Generate INFO file ─────────────────────────────────────────────────
echo ""
echo "[5/6] Generating INFO file..."

INFO_FILE="${WORK_DIR}/INFO"
# Substitute variables in template
sed -e "s|\${JELLYFIN_VERSION}|${JELLYFIN_VERSION}|g" \
    -e "s|\${CHECKSUM}|${CHECKSUM}|g" \
    "${TEMPLATE_DIR}/INFO.template" > "$INFO_FILE"

chmod 755 "$INFO_FILE"
echo "  INFO file generated:"
cat "$INFO_FILE"

# ── Step 6: Assemble SPK ───────────────────────────────────────────────────────
echo ""
echo "[6/6] Assembling SPK package..."

SPK_NAME="jellyfin_v${JELLYFIN_VERSION}-${SPK_ARCH}_DSM7.2+.spk"
SPK_PATH="${OUTPUT_DIR}/${SPK_NAME}"

# Create SPK staging directory
SPK_STAGE="${WORK_DIR}/spk_stage"
mkdir -p "${SPK_STAGE}"

# Copy all components into staging
cp "$INFO_FILE" "${SPK_STAGE}/"
cp "${TEMPLATE_DIR}/PACKAGE_ICON.PNG" "${SPK_STAGE}/"
cp "${TEMPLATE_DIR}/PACKAGE_ICON_256.PNG" "${SPK_STAGE}/"
cp -a "${TEMPLATE_DIR}/conf" "${SPK_STAGE}/"
cp -a "${TEMPLATE_DIR}/scripts" "${SPK_STAGE}/"
cp -a "${TEMPLATE_DIR}/WIZARD_UIFILES" "${SPK_STAGE}/"
cp "${WORK_DIR}/package.tgz" "${SPK_STAGE}/"

# Create SPK (tar archive, matching old package file order)
cd "$SPK_STAGE"
tar -cf "$SPK_PATH" \
    conf \
    scripts \
    INFO \
    PACKAGE_ICON_256.PNG \
    PACKAGE_ICON.PNG \
    package.tgz \
    WIZARD_UIFILES
cd - > /dev/null

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ SPK built successfully!"
echo "════════════════════════════════════════════════════════════════"
echo "  Output: ${SPK_PATH}"
echo "  Size:   $(du -h "$SPK_PATH" | cut -f1)"
echo "  Name:   ${SPK_NAME}"
echo "════════════════════════════════════════════════════════════════"

# Verify SPK structure
echo ""
echo "  SPK contents:"
tar -tf "$SPK_PATH" | while read f; do
    echo "    $f"
done

# Clean up work directory
rm -rf "$WORK_DIR"

echo ""
echo "Done."
