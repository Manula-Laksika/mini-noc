#!/usr/bin/env bash
# Usage: disk-check.sh <mount-point> <push-url-without-query>
MOUNT="$1"
PUSH_URL="$2"
THRESHOLD=90

USED=$(df --output=pcent "$MOUNT" | tail -1 | tr -dc '0-9')
MSG="Disk%20${MOUNT}%20at%20${USED}%25"

if [ "$USED" -ge "$THRESHOLD" ]; then
  curl -fsS -m 10 "${PUSH_URL}?status=down&msg=${MSG}" >/dev/null
else
  curl -fsS -m 10 "${PUSH_URL}?status=up&msg=${MSG}" >/dev/null
fi