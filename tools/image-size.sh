#!/bin/sh
# Prints the compressed size, in bytes, of an image in a registry: the sum of
# its linux/amd64 layer sizes, which is what a pull downloads. Works on a
# single manifest or an index.
# usage: tools/image-size.sh <registry/name:tag>
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <image-ref>" >&2; exit 2; }
ref=$1
raw="$(docker buildx imagetools inspect --raw "$ref")"
if ! printf '%s' "$raw" | jq -e '.layers' >/dev/null 2>&1; then
  digest="$(printf '%s' "$raw" | jq -r '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")][0].digest')"
  raw="$(docker buildx imagetools inspect --raw "${ref%:*}@${digest}")"
fi
printf '%s' "$raw" | jq '[.layers[].size] | add'
