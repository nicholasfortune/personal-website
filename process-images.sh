#!/bin/bash

# Nick was here 11/08/2026
# Nick was here again at 18/08/2026
# Takes images in ./assets/images/input, compresses them into 4 AVIF tiers + 1 WebP fallback.
# vibecoded slop poo from here on out

# 1. Validate dependencies
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required but not installed." >&2
    exit 1
fi

shopt -s nullglob nocaseglob

BASE_DIR="./assets/images"

if [ ! -d "$BASE_DIR" ]; then
    echo "Error: Base directory '$BASE_DIR' does not exist!" >&2
    exit 1
fi

# 2. Discover all 'input' subdirectories under assets/images
mapfile -t input_dirs < <(find "$BASE_DIR" -type d -name "input")

if [ ${#input_dirs[@]} -eq 0 ]; then
    echo "Error: No 'input' directories found in $BASE_DIR." >&2
    exit 1
fi

files=()
skipped_dirs=0

# 3. Check for existing output directories and gather files
for d in "${input_dirs[@]}"; do
    parent=$(dirname "$d")
    
    if [ -d "$parent/low" ] && [ -d "$parent/medium" ] && [ -d "$parent/high" ] && [ -d "$parent/ultra" ] && [ -d "$parent/fallback" ]; then
        skipped_dirs=$((skipped_dirs + 1))
        continue
    fi

    mkdir -p "$parent/low" "$parent/medium" "$parent/high" "$parent/ultra" "$parent/fallback"
    
    for img in "$d"/*.jpg "$d"/*.jpeg "$d"/*.png "$d"/*.webp "$d"/*.jxl; do
        [ -f "$img" ] && files+=("$img")
    done
done

total_files=${#files[@]}

if [ "$total_files" -eq 0 ]; then
    if [ "$skipped_dirs" -gt 0 ]; then
        echo "Notice: All $skipped_dirs discovered input folder(s) were skipped because output directories already exist."
        exit 0
    fi
    echo "Error: No valid .jpg, .jpeg, .png, .webp, or .jxl files found to process." >&2
    exit 1
fi

# 4. Setup Cleanup Trap (Restores normal screen buffer & scroll region)
cleanup() {
    printf "\033[r"    # Reset scrolling region to default (full screen)
    tput cnorm         # Restore cursor
    tput rmcup         # Restore original terminal screen buffer
}
trap cleanup EXIT INT TERM

# 5. Handle Terminal Window Resizing (SIGWINCH)
update_terminal_dimensions() {
    cols=$(tput cols)
    rows=$(tput lines)
    if [ "$rows" -ge 6 ]; then
        printf "\033[1;%dr" "$((rows - 1))" # Scroll region: line 1 to (rows-1)
    fi
}
trap update_terminal_dimensions WINCH

cols=$(tput cols)
rows=$(tput lines)

if [ "$rows" -lt 6 ]; then
    echo "Error: Terminal window must be at least 6 rows high (current: $rows)." >&2
    exit 1
fi

# 6. Setup Terminal UI layout in alternate screen buffer
tput smcup             # Save terminal state & enter alternate screen buffer
clear                  # Clear alternate screen
tput civis             # Hide cursor

# Set active scrolling margin (rows 1 to rows-1)
printf "\033[1;%dr" "$((rows - 1))"
tput cup 0 0

start_time=$(date +%s)
current=0

# Helper function: Render status bar cleanly on bottom row
render_status_bar() {
    local text="$1"
    local bg_color="$2"  # ANSI color codes: 44=Blue, 42=Green
    local fg_color="$3"  # ANSI color codes: 37=White, 30=Black
    
    tput sc                                                         # Save cursor position
    tput cup $((rows - 1)) 0                                        # Move to bottom row
    printf "\033[%s;%sm%-*s\033[0m" "$bg_color" "$fg_color" "$cols" "$text" # Print full-width bar
    tput rc                                                         # Restore cursor position
}

# 7. Main processing loop
for img in "${files[@]}"; do
    [ -f "$img" ] || continue
    current=$((current + 1))
    
    input_dir=$(dirname "$img")
    parent_dir=$(dirname "$input_dir")
    filename=$(basename "$img")
    name="${filename%.*}"

    rel_path="${img#./}"
    echo "Processing ($current/$total_files): $rel_path"

    # Encode AVIF Low
    ffmpeg -y -i "$img" -map_metadata -1 -vf "scale=400:-2:flags=lanczos" -c:v libsvtav1 -preset 2 -crf 25 -b:v 0 "$parent_dir/low/${name}.avif" -v quiet || {
        echo "Warning: Failed low AVIF for $filename"
    }

    # Encode AVIF Medium
    ffmpeg -y -i "$img" -map_metadata -1 -vf "scale=800:-2:flags=lanczos" -c:v libsvtav1 -preset 2 -crf 25 -b:v 0 "$parent_dir/medium/${name}.avif" -v quiet || {
        echo "Warning: Failed medium AVIF for $filename"
    }

    # Encode AVIF High
    ffmpeg -y -i "$img" -map_metadata -1 -vf "scale=1200:-2:flags=lanczos" -c:v libsvtav1 -preset 2 -crf 18 -b:v 0 "$parent_dir/high/${name}.avif" -v quiet || {
        echo "Warning: Failed high AVIF for $filename"
    }

    # Encode AVIF Ultra
    ffmpeg -y -i "$img" -map_metadata -1 -vf "scale=2400:-2:flags=lanczos" -c:v libsvtav1 -preset 2 -crf 18 -b:v 0 "$parent_dir/ultra/${name}.avif" -v quiet || {
        echo "Warning: Failed ultra AVIF for $filename"
    }

    # Encode WebP Fallback
    ffmpeg -y -i "$img" -map_metadata -1 -vf "scale=400:-2:flags=lanczos" -c:v libwebp -compression_level 6 -q:v 90 "$parent_dir/fallback/${name}.webp" -v quiet || {
        echo "Warning: Failed WebP fallback for $filename"
    }

    echo "Success: $filename"

    # Real-time stats
    now=$(date +%s)
    elapsed=$((now - start_time))
    
    if [ "$current" -gt 0 ] && [ "$elapsed" -gt 0 ]; then
        avg_time_ms=$(( (elapsed * 1000) / current ))
        remaining_items=$((total_files - current))
        eta_secs=$(( (avg_time_ms * remaining_items) / 1000 ))
        eta=$(printf "%02d:%02d" $((eta_secs / 60)) $((eta_secs % 60)))
    else
        eta="--:--"
    fi

    elapsed_fmt=$(printf "%02d:%02d" $((elapsed / 60)) $((elapsed % 60)))
    percent=$((current * 100 / total_files))

    # Bottom status bar render (Blue background)
    bar_text=" STATS | Progress: [$current/$total_files] ($percent%) | Elapsed: $elapsed_fmt | ETA: $eta "
    render_status_bar "$bar_text" "44" "37"
done

# Completion display (Green background)
done_text=" COMPLETED | Successfully processed $total_files file(s). Press any key to exit. "
render_status_bar "$done_text" "42" "30"

read -n 1 -s
