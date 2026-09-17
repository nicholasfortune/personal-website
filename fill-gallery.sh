#!/usr/bin/env bash

# even more vibecoded poo mush coming up 15/09/2026
# I'm probably never gonna learn bash, it seems like such a boring language lol
# learning the intricacies of so many rapidly evolving systems with seemingly arbitrary interfaces just to put them together for a one-off thing seems like a terrible ROI anyway
# anyway that's the end of my thoughts
# I'm back 16/09/2026, there was an issue with layout shifting I noticed on a different implimentation, I think I fixed it with more AI.

set -euo pipefail

ULTRA_DIR="./assets/images/gallery/ultra"
GALLERY_FILE="gallery.html"

if [[ ! -d "$ULTRA_DIR" ]]; then
  echo "Error: Directory '$ULTRA_DIR' does not exist." >&2
  exit 1
fi

if [[ ! -f "$GALLERY_FILE" ]]; then
  echo "Error: File '$GALLERY_FILE' does not exist." >&2
  exit 1
fi

# Create temporary files in local directory for atomic file operations
BLOCKS_FILE=$(mktemp ./gallery_blocks.XXXXXX)
TMP_FILE=$(mktemp ./gallery_tmp.XXXXXX)

cleanup() {
  rm -f "$BLOCKS_FILE" "$TMP_FILE"
}
trap cleanup EXIT

shopt -s nullglob
files=("$ULTRA_DIR"/*)

# Filter for regular non-hidden files
valid_files=()
for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  filename=$(basename "$f")
  [[ "$filename" =~ ^\. ]] && continue
  valid_files+=("$f")
done

# Sort files naturally (img1, img2, img10)
IFS=$'\n' sorted_files=($(printf '%s\n' "${valid_files[@]}" | sort -V))
unset IFS

# Helper function to extract width and height using available CLI tools
get_image_dimensions() {
  local img_path="$1"
  local dimensions=""

  if command -v identify >/dev/null 2>&1; then
    dimensions=$(identify -format "%w %h" "$img_path" 2>/dev/null || true)
  elif command -v ffprobe >/dev/null 2>&1; then
    dimensions=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=nw=1:nk=1 "$img_path" 2>/dev/null | xargs || true)
  elif command -v exiftool >/dev/null 2>&1; then
    dimensions=$(exiftool -s3 -ImageWidth -ImageHeight "$img_path" 2>/dev/null | xargs || true)
  fi

  echo "$dimensions"
}

# Escape HTML special characters for inner text/attributes
html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&#39;}"
  printf '%s' "$s"
}

# Percent-encode special characters for URLs
url_encode() {
  local s="$1"
  local length="${#s}"
  local i char
  for (( i = 0; i < length; i++ )); do
    char="${s:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-]) printf '%s' "$char" ;;
      *) printf '%%%02X' "'$char" ;;
    esac
  done
}

# Generate whitespace-minified HTML template blocks with progress bar and aspect ratio
total_images=${#sorted_files[@]}

if [[ "$total_images" -gt 0 ]]; then
  start_time=$(date +%s)
  bar_width=25

  for i in "${!sorted_files[@]}"; do
    file="${sorted_files[$i]}"
    current=$((i + 1))

    # Calculate Progress and ETA
    now=$(date +%s)
    elapsed=$((now - start_time))

    if (( elapsed > 0 && current > 0 )); then
      remaining_items=$((total_images - current))
      eta_seconds=$(( (elapsed * remaining_items) / current ))
    else
      eta_seconds=0
    fi

    percent=$(( current * 100 / total_images ))
    filled=$(( percent * bar_width / 100 ))
    empty=$(( bar_width - filled ))

    # Generate progress bar characters
    printf -v filled_str '%*s' "$filled" ''
    filled_str="${filled_str// /#}"
    printf -v empty_str '%*s' "$empty" ''
    empty_str="${empty_str// /-}"

    # Format ETA output (MM:SS)
    eta_min=$((eta_seconds / 60))
    eta_sec=$((eta_seconds % 60))
    eta_fmt=$(printf "%02dm%02ds" "$eta_min" "$eta_sec")

    # Render terminal progress bar over stderr
    printf "\rProgress: [%s%s] %d/%d (%d%%) | ETA: %s" "$filled_str" "$empty_str" "$current" "$total_images" "$percent" "$eta_fmt" >&2

    filename=$(basename "$file")
    raw_name="${filename%.*}"

    enc_name=$(url_encode "$raw_name")
    disp_name=$(html_escape "$raw_name")

    style_attr=""
    read -r img_w img_h <<< "$(get_image_dimensions "$file")"

    if [[ -n "${img_w:-}" && -n "${img_h:-}" ]]; then
      style_attr=" style=\"aspect-ratio: ${img_w} / ${img_h};\""
    fi

    cat <<EOF >> "$BLOCKS_FILE"
<a href="/assets/images/gallery/ultra/${enc_name}.avif" class="sub"><picture><source srcset="/assets/images/gallery/low/${enc_name}.avif 400w, /assets/images/gallery/medium/${enc_name}.avif 800w, /assets/images/gallery/high/${enc_name}.avif 1200w, /assets/images/gallery/ultra/${enc_name}.avif 2400w" sizes="(max-width: 768px) 90vw, (max-width: 1280px) 35.5vw, 484px" type="image/avif" /><img src="/assets/images/gallery/fallback/${enc_name}.webp"${style_attr} class="gallery-images" loading="lazy" decoding="async" /></picture><p class="gallery-subtitle">/assets/images/gallery/ultra/${disp_name}.avif</p></a>
EOF
  done
  printf "\n" >&2
fi

# AWK processor using tag depth tracking for infinite re-run safety
awk -v blocks_file="$BLOCKS_FILE" '
BEGIN {
    in_container = 0
    depth = 0
    replaced = 0
}

/<div[[:space:]]+class=["\x27]gallery-container["\x27][^>]*>/ {
    if (!replaced) {
        print $0
        while ((getline line < blocks_file) > 0) {
            print line
        }
        close(blocks_file)

        line_tail = $0
        sub(/.*<div[[:space:]]+class=["\x27]gallery-container["\x27][^>]*>/, "", line_tail)
        
        tmp1 = line_tail; opens = gsub(/<div[[:space:]>]/, "&", tmp1)
        tmp2 = line_tail; closes = gsub(/<\/div>/, "&", tmp2)
        
        depth = 1 + opens - closes
        replaced = 1
        
        if (depth <= 0) {
            in_container = 0
        } else {
            in_container = 1
        }
        next
    }
}

in_container {
    tmp1 = $0; opens = gsub(/<div[[:space:]>]/, "&", tmp1)
    tmp2 = $0; closes = gsub(/<\/div>/, "&", tmp2)
    depth += opens - closes

    if (depth <= 0) {
        in_container = 0
        print $0
    }
    next
}

!in_container {
    print $0
}
' "$GALLERY_FILE" > "$TMP_FILE"

mv "$TMP_FILE" "$GALLERY_FILE"
echo "Successfully updated $GALLERY_FILE."