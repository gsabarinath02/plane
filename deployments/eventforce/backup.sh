#!/usr/bin/env bash
set -Eeuo pipefail

readonly APP_DIR="/opt/plane"
readonly ENV_FILE="${APP_DIR}/runtime.env"
readonly BACKUP_ROOT="${APP_DIR}/backups"
readonly TIMESTAMP="$(date --utc +%Y%m%dT%H%M%SZ)"
readonly BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

source "${ENV_FILE}"
mkdir -p "${BACKUP_DIR}"
chmod 0700 "${BACKUP_ROOT}" "${BACKUP_DIR}"

docker exec plane-staging-plane-db-1 \
  pg_dump --clean --if-exists --no-owner --username "${POSTGRES_USER}" "${POSTGRES_DB}" |
  gzip -9 > "${BACKUP_DIR}/plane.sql.gz"

docker run --rm \
  --volume plane-staging_uploads:/source:ro \
  --volume "${BACKUP_DIR}:/backup" \
  alpine:3.22 \
  tar -C /source -czf /backup/uploads.tar.gz .

sha256sum "${BACKUP_DIR}"/* > "${BACKUP_DIR}/SHA256SUMS"
aws s3 cp "${BACKUP_DIR}" "s3://${BACKUP_BUCKET}/${TIMESTAMP}/" --recursive --only-show-errors
rm -rf "${BACKUP_DIR}"
