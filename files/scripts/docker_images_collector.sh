#!/bin/bash
set -euo pipefail

OUTPUT=/var/lib/alloy/textfile/docker_images.prom
TMPFILE=$(mktemp)
HOSTNAME=$(hostname)

echo "# HELP docker_image_info Docker images present on host" > "$TMPFILE"
echo "# TYPE docker_image_info gauge" >> "$TMPFILE"

RUNNING_IMAGES=$(docker ps --format '{{.Image}}')

docker images --no-trunc --format '{{.Repository}}|{{.Tag}}|{{.ID}}' \
| while IFS='|' read -r repo tag id; do
  [ "$repo" = "<none>" ] && continue
  [ "$tag"  = "<none>" ] && continue

  image="${repo}:${tag}"
  short_id=$(echo "$id" | sed 's/sha256://' | cut -c1-12)

  if echo "$RUNNING_IMAGES" | grep -qx "$image"; then
    in_use="U"
  else
    in_use=""
  fi

  echo "docker_image_info{image=\"${image}\",id=\"${short_id}\",instance=\"${HOSTNAME}\",in_use=\"${in_use}\"} 1" >> "$TMPFILE"
done

mv "$TMPFILE" "$OUTPUT"
chmod 644 "$OUTPUT"
