#!/bin/sh
# Prints the compressed size, in bytes, of an image: the sum of the sizes of its
# linux/amd64 layer blobs, which is what a registry pull downloads. The image is
# either
#   - a registry reference (`ghcr.io/org/name:tag`; single manifest or index), or
#   - an OCI image-layout tarball, i.e. an existing file, as written by
#     `docker buildx build --output type=oci,dest=image.tar` (index.json inside).
# Attestation manifests are ignored (only the linux/amd64 image is measured), and
# so is the tar's own overhead: the number is the sum of the layer descriptors, not
# the file size, so the two sources are comparable.
#
# stdout: the total in bytes, and nothing else (safe in $(...)).
# --layers: also print a per-layer table to stderr (size, compression, and the
# `created_by` of the matching config-history entry), so a job log shows where
# the bytes come from.
#
# A tarball layer that is not compressed (a builder run with compression=
# uncompressed) has no meaningful "compressed" size in the descriptor; it is
# gzip-compressed on the fly instead and marked in the table.
#
# needs: jq; docker buildx (registry references only; no daemon required); tar,
# gzip (tarballs only).
# usage: tools/image-size.sh [--layers] <registry/name:tag | oci-layout.tar>
set -eu

usage() { echo "usage: $0 [--layers] <registry/name:tag | oci-layout.tar>" >&2; exit 2; }
die() { echo "image-size: $*" >&2; exit 1; }

layers=0
if [ "${1:-}" = "--layers" ]; then layers=1; shift; fi
[ $# -eq 1 ] || usage
src=$1

# Stdin: an image manifest or an index. Prints the linux/amd64 child digest of an
# index (attestation manifests are platform unknown/unknown, so never match).
child_digest() {
  jq -r '[.manifests[] | select(.platform == null or (.platform.os == "linux" and .platform.architecture == "amd64"))][0].digest // empty'
}

if [ -f "$src" ]; then
  mode=tar
  # One blob out of the tarball. --occurrence stops the scan at the first match.
  tar_member() { tar -xOf "$src" --occurrence=1 "$1"; }
  tar_blob() { tar_member "blobs/sha256/${1#sha256:}"; }
  doc="$(tar_member index.json)"
  while ! printf '%s' "$doc" | jq -e '.layers' >/dev/null 2>&1; do
    digest="$(printf '%s' "$doc" | child_digest)"
    [ -n "$digest" ] || die "no linux/amd64 image in $src"
    doc="$(tar_blob "$digest")"
  done
  manifest=$doc
  config="$(tar_blob "$(printf '%s' "$manifest" | jq -r '.config.digest')")"
else
  mode=registry
  command -v docker >/dev/null 2>&1 || die "docker (buildx) is required to read a registry image"
  case "$src" in *@*) repo=${src%@*} ;; *) repo=${src%:*} ;; esac
  doc="$(docker buildx imagetools inspect --raw "$src")"
  if ! printf '%s' "$doc" | jq -e '.layers' >/dev/null 2>&1; then
    digest="$(printf '%s' "$doc" | child_digest)"
    [ -n "$digest" ] || die "no linux/amd64 image in $src"
    src="${repo}@${digest}"
    doc="$(docker buildx imagetools inspect --raw "$src")"
  fi
  manifest=$doc
  # The image config (with the build history) of that one manifest.
  config="$(docker buildx imagetools inspect --format '{{json .Image}}' "$src")"
fi

# Effective size of each layer: the descriptor's, unless (tarball only) the blob
# is uncompressed, in which case measure it as gzip would store it.
sizes='[]'
measured='[]'
n="$(printf '%s' "$manifest" | jq '.layers | length')"
i=0
while [ "$i" -lt "$n" ]; do
  row="$(printf '%s' "$manifest" | jq -r ".layers[$i] | [.digest, .size, .mediaType] | @tsv")"
  digest="$(printf '%s' "$row" | cut -f1)"
  size="$(printf '%s' "$row" | cut -f2)"
  media="$(printf '%s' "$row" | cut -f3)"
  is_measured=false
  if [ "$mode" = tar ]; then
    case "$media" in
      *gzip* | *zstd*) ;;
      *) size="$(tar_blob "$digest" | gzip -6 -c | wc -c | tr -d ' ')"; is_measured=true ;;
    esac
  fi
  sizes="$(printf '%s' "$sizes" | jq -c ". + [$size]")"
  measured="$(printf '%s' "$measured" | jq -c ". + [$is_measured]")"
  i=$((i + 1))
done

total="$(printf '%s' "$sizes" | jq 'add // 0')"

if [ "$layers" = 1 ]; then
  # History entries with a layer, in order, line up with manifest.layers. The
  # `|N ARG=… /bin/bash -o pipefail -c ` BuildKit puts after RUN is noise: strip it.
  jq -rn --argjson m "$manifest" --argjson c "$config" --argjson sizes "$sizes" --argjson measured "$measured" '
    def clean:
      gsub("[ \t\n]+"; " ")
      | sub("^RUN \\|[0-9]+ ([^ =]+=[^ ]* )*"; "RUN ")
      | sub("^RUN /bin/(ba)?sh (-o pipefail )?-c "; "RUN ")
      | sub(" # buildkit$"; "");
    def comp: if test("gzip") then "gzip" elif test("zstd") then "zstd" else "none" end;
    [($c.history // [])[] | select(.empty_layer | not) | (.created_by // "")] as $by
    | $m.layers | to_entries[]
    | [ $sizes[.key],
        (.value.mediaType | comp) + (if $measured[.key] then "*" else "" end),
        ($by[.key] // "(no history)" | clean | .[0:110]) ]
    | @tsv' \
    | awk -F'\t' 'BEGIN { printf "%15s %11s  %-5s  %s\n", "bytes", "size", "comp", "created_by" }
                  { printf "%15d %8.1f MiB  %-5s  %s\n", $1, $1 / 1048576, $2, $3 }' >&2
  printf '%15d %8.1f MiB  total, %s layers (%s)\n' \
    "$total" "$(awk -v b="$total" 'BEGIN { printf "%.1f", b / 1048576 }')" "$n" "$mode" >&2
  if [ "$(printf '%s' "$measured" | jq 'any')" = true ]; then
    echo "  * not compressed in the source: size is what gzip -6 makes of the layer" >&2
  fi
fi

printf '%s\n' "$total"
