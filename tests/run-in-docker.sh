#!/usr/bin/env bash
# Usage: tests/run-in-docker.sh ubuntu:22.04|rockylinux:9
# Applies all roles twice inside a container and fails unless the second run reports changed=0.
# A third run in --check mode must report changed=0 as well.
set -euo pipefail
image="${1:?image}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
name="baseline-test-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

retry() { for _ in 1 2 3; do "$@" && return 0; sleep 5; done; return 1; }

docker run -d --name "$name" -v "$repo:/repo:ro" "$image" sleep 3600 >/dev/null
case "$image" in
  ubuntu*|debian*)
    retry docker exec "$name" bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pip tar ca-certificates openssh-server >/dev/null' ;;
  *)
    retry docker exec "$name" bash -c 'dnf clean all >/dev/null; dnf install -y -q python3-pip tar openssh-server >/dev/null' ;;
esac
# PEP 668: Debian 12 refuses system-wide pip installs; this is a throwaway container.
docker exec -e PIP_BREAK_SYSTEM_PACKAGES=1 "$name" pip3 install -q --retries 8 --timeout 60 'ansible-core>=2.15,<2.16' 2>&1 | grep -v WARNING || true

# Offline mirror with a dummy node_exporter, so the download/checksum/unpack logic is tested
# without depending on GitHub. The real release URL is not exercised here.
docker exec "$name" bash -c '
  v=1.8.2; arch=$(uname -m); [ "$arch" = x86_64 ] && arch=amd64 || arch=arm64
  d=/tmp/mirror/v$v; mkdir -p $d /tmp/build/node_exporter-$v.linux-$arch
  printf "#!/bin/sh\necho dummy\n" > /tmp/build/node_exporter-$v.linux-$arch/node_exporter
  chmod +x /tmp/build/node_exporter-$v.linux-$arch/node_exporter
  tar -C /tmp/build -czf $d/node_exporter-$v.linux-$arch.tar.gz node_exporter-$v.linux-$arch
  (cd $d && sha256sum *.tar.gz > sha256sums.txt)
  cd /tmp/mirror && nohup python3 -m http.server 8000 >/dev/null 2>&1 &
  sleep 1'

run() {
  docker exec -e ANSIBLE_ROLES_PATH=/repo/roles -e ANSIBLE_LOCALHOST_WARNING=false "$name" \
    sh -c 'mkdir -p /run/sshd && ssh-keygen -A >/dev/null 2>&1 || true; ansible-playbook /repo/tests/converge.yml -e node_exporter_download_base=http://127.0.0.1:8000 "$@"' sh "$@"
}
echo "== first run"; run | grep -E "fatal|PLAY RECAP|^localhost" | cut -c1-400
echo "== second run (must be changed=0)"
# with set -e a failed run would exit here before anything is printed, so show the tail first
out="$(run)" || { echo "$out" | tail -n 20; echo "SECOND RUN FAILED"; exit 1; }
echo "$out" | grep -E "fatal|FAILED|PLAY RECAP|^localhost" | cut -c1-400
echo "$out" | grep -Eq 'changed=0 .*failed=0' || { echo "NOT IDEMPOTENT"; exit 1; }
echo "== third run, --check (must be changed=0)"
out="$(run --check)" || { echo "$out" | tail -n 20; echo "CHECK RUN FAILED"; exit 1; }
echo "$out" | grep -E "fatal|FAILED|PLAY RECAP|^localhost" | cut -c1-400
echo "$out" | grep -Eq 'changed=0 .*failed=0' || { echo "CHECK MODE REPORTS CHANGES"; exit 1; }
echo "OK: $image idempotent"
