#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Usage: $0 <40-character Git commit SHA>" >&2
  exit 64
fi

readonly RELEASE_SHA="$1"
readonly APP_DIR="/opt/plane"
readonly ENV_FILE="${APP_DIR}/runtime.env"
readonly COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
readonly REPOSITORY="gsabarinath02/plane"
readonly COMPOSE_URL="https://raw.githubusercontent.com/${REPOSITORY}/${RELEASE_SHA}/deployments/eventforce/docker-compose.staging.yml"

exec 9>"${APP_DIR}/deploy.lock"
flock -n 9 || { echo "Another Plane deployment is already running" >&2; exit 75; }

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}; infrastructure bootstrap has not completed" >&2
  exit 78
fi

previous_tag="$(sed -n 's/^IMAGE_TAG=//p' "${ENV_FILE}" | tail -n 1)"
tmp_compose="$(mktemp "${APP_DIR}/docker-compose.XXXXXX")"
trap 'rm -f "${tmp_compose}"' EXIT

curl --fail --silent --show-error --location "${COMPOSE_URL}" --output "${tmp_compose}"
grep -q '^name: plane-staging$' "${tmp_compose}"

source "${ENV_FILE}"
aws ecr get-login-password --region "${AWS_REGION}" |
  docker login --username AWS --password-stdin "${ECR_REPOSITORY%%/*}"

sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=${RELEASE_SHA}/" "${ENV_FILE}"
install -m 0644 "${tmp_compose}" "${COMPOSE_FILE}"

compose() {
  docker compose --env-file "${ENV_FILE}" --file "${COMPOSE_FILE}" "$@"
}

rollback() {
  if [[ -n "${previous_tag}" && "${previous_tag}" != "bootstrap" ]]; then
    echo "Deployment health check failed; rolling back to ${previous_tag}" >&2
    sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=${previous_tag}/" "${ENV_FILE}"
    compose up --detach --remove-orphans
  fi
}
trap rollback ERR

compose config --quiet
compose pull
compose up --detach plane-db plane-redis plane-mq plane-minio
compose run --rm migrator
compose up --detach --remove-orphans web space admin live api worker beat-worker proxy

for attempt in {1..60}; do
  if curl --fail --silent --show-error --max-time 5 http://127.0.0.1/ >/dev/null; then
    printf '{"commit":"%s","deployed_at":"%s"}\n' \
      "${RELEASE_SHA}" "$(date --utc +%Y-%m-%dT%H:%M:%SZ)" > "${APP_DIR}/deployment.json"
    chmod 0644 "${APP_DIR}/deployment.json"
    trap - ERR
    compose ps
    exit 0
  fi
  sleep 5
done

echo "Plane did not become healthy within 5 minutes" >&2
exit 1
