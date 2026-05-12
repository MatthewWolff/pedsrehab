#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SFTP_HOST="pedsrehab-sandbox"
SFTP_PASS="${PEDSREHAB_SFTP_PASS:?Set PEDSREHAB_SFTP_PASS environment variable}"
SOURCE_DOMAIN="wolff.sh/pedsrehab"

usage() {
  echo "Usage: $0 [--sandbox | --production]"
  echo ""
  echo "  --sandbox     Deploy to sandbox.pedsrehab.org (default)"
  echo "  --production  Deploy to pedsrehab.org"
  exit 1
}

SKIP_CONFIRM=false
for arg in "$@"; do
  case "$arg" in
    --sandbox)    TARGET="sandbox" ;;
    --production) TARGET="production" ;;
    --yes|-y)     SKIP_CONFIRM=true ;;
    -h|--help)    usage ;;
    *)            usage ;;
  esac
done
TARGET="${TARGET:-sandbox}"

if [[ "$TARGET" == "sandbox" ]]; then
  TARGET_DOMAIN="sandbox.pedsrehab.org"
else
  TARGET_DOMAIN="pedsrehab.org"
fi

echo "==> Deploying to $TARGET_DOMAIN"

# Create a staging directory with rewritten URLs
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"; rm -f "${BATCH:-}"' EXIT

echo "==> Staging files in $STAGE"
rsync -a --exclude='.git' --exclude='docs' --exclude='deploy.sh' --exclude='.gitignore' --exclude='.superpowers' --exclude='.DS_Store' --exclude='.playwright-mcp' --exclude='*.zip' "$SCRIPT_DIR/" "$STAGE/"

echo "==> Rewriting URLs: $SOURCE_DOMAIN -> $TARGET_DOMAIN"
find "$STAGE" \( -name '*.html' -o -name '*.xml' -o -name 'robots.txt' \) \
  -exec sed -i '' -e "s|https://$SOURCE_DOMAIN/|https://$TARGET_DOMAIN/|g" \
                  -e "s|https://$SOURCE_DOMAIN|https://$TARGET_DOMAIN|g" {} +

echo "==> Generating SFTP batch commands"
BATCH=$(mktemp)

# Remove old remote content (nested subdirs first, then top-level)
for item in assets/img assets/styles about assets contact forms insurance locations messages patientresources resources; do
  echo "-rm ${item}/*" >> "$BATCH"
  echo "-rmdir ${item}" >> "$BATCH"
done
echo "-rm 404.html" >> "$BATCH"
echo "-rm index.html" >> "$BATCH"
echo "-rm .DS_Store" >> "$BATCH"

# Upload new content
echo "put ${STAGE}/index.html index.html" >> "$BATCH"
echo "put ${STAGE}/favicon.svg favicon.svg" >> "$BATCH"
echo "put ${STAGE}/robots.txt robots.txt" >> "$BATCH"
echo "put ${STAGE}/sitemap.xml sitemap.xml" >> "$BATCH"

for html in about contact forms insurance locations patientresources resources; do
  echo "put ${STAGE}/${html}.html ${html}.html" >> "$BATCH"
done

echo "mkdir assets" >> "$BATCH"
echo "mkdir assets/images" >> "$BATCH"
for img in "$STAGE"/assets/images/*; do
  echo "put ${img} assets/images/$(basename "$img")" >> "$BATCH"
done

echo "mkdir resources" >> "$BATCH"
for pdf in "$STAGE"/resources/*; do
  echo "put ${pdf} resources/$(basename "$pdf")" >> "$BATCH"
done

echo ""
echo "==> Ready to upload. Review the batch commands:"
echo "---"
cat "$BATCH"
echo "---"
echo ""
if [[ "$SKIP_CONFIRM" != true ]]; then
  read -p "Proceed with upload to $TARGET_DOMAIN? [y/N] " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "==> Uploading via SFTP..."
sshpass -p "$SFTP_PASS" sftp -oPubkeyAuthentication=no "$SFTP_HOST" < "$BATCH"

echo "==> Done! Site deployed to https://$TARGET_DOMAIN/"
