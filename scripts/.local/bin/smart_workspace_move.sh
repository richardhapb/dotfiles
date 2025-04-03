#!/usr/bin/env bash

if ! command -v "xdotool" > /dev/null 2>&1; then
    echo "xdotool not installed, you can install it with sudo apt install xdotool."
    exit 1
fi

WS_NUM="$1"

if [ -z "$WS_NUM" ]; then
    echo "Error: Workspace number is required" >&2
    exit 1
elif ! [[ "$WS_NUM" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Workspace number must be a positive integer" >&2
    exit 1
fi

# Get the focused window information
FOCUSED_WINDOW=$(xprop -root | grep "_NET_ACTIVE_WINDOW(WINDOW)" | awk '{print $NF}')
WINDOW_CLASS=$(xprop -id "$FOCUSED_WINDOW" WM_CLASS 2>/dev/null | grep -o '"[^"]*"' | tail -n 1 | tr -d '"')

process_name() {
    local pid=$(xdotool getwindowfocus getwindowpid)
    # Get all child processes
    ps --ppid "$pid" -o comm= || echo ""
}

# Function to check if i'm in vim/neovim
is_vim() {
    echo "===="
    echo "$(process_name)"
    if [ "$(process_name)" | grep -q "sh" ]; then
        return 0
    else
        return 1
    fi
}

# For change workspace in a browser need to
# trigger the script two times
is_second_press() {
    local window_id="$FOCUSED_WINDOW"
    local temp_file="/tmp/workspace_move_${window_id}_${USER}"
    local timeout=1  # seconds

    echo "$(process_name)"

    if [ "$(process_name)" | grep -qiE "brave|firefox" ]; then
        return 1
    fi

    echo "init"
    # Cleanup on script exit
    trap 'rm -f "$temp_file"' EXIT
    echo "init2"

    # Check if temp file exists and is not stale
    if [ -f "$temp_file" ]; then
        echo "EXISTS"
        local file_time=$(stat -c %Y "$temp_file")
        local current_time=$(date +%s)
        
        rm -f "$temp_file"
        
        # Check if file is not older than timeout
        if [ $((current_time - file_time)) -le $timeout ]; then
            return 0  # True - this is a second press
        fi
    fi
    echo "DONT"

    touch "$temp_file"
    return 1  # False - this is first press
}

# Check if we're in a terminal or browser
if echo "$WINDOW_CLASS" | grep -qiE "term|kitty|alacritty|wezterm|ghostty|gnome-terminal|[Bb]rave-*[Bb]rowser|firefox"; then
    # In Vim/Neovim or first attempt in a browser - send the open exclamation character
    if is_vim || ! is_second_press; then
        xdotool type "¡"
    else
        # Not in insert mode or not in Vim - move the container
        i3-msg "move container to workspace number $WS_NUM"
    fi
else
    # Not in a terminal - move the container
    i3-msg "move container to workspace number $WS_NUM"
fi

