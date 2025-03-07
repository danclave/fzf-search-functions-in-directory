# Main function picker
fzf-func() {
    # Check if SCRIPTS directory is set
    if [[ -z "$SCRIPTS" ]]; then
        echo "Error: \$SCRIPTS environment variable not set."
        echo "Please set it to your scripts directory, e.g.: export SCRIPTS=~/scripts"
        return 1
    fi

    # Check if fzf is installed
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is not installed. Please install it first."
        return 1
    fi

    # Check if bat is installed
    if ! command -v bat >/dev/null 2>&1; then
        echo "Notice: bat is not installed. Syntax highlighting will be disabled. Or it might not work at all. Idk, just install bat."
    fi

    # Parse arguments
    local edit_mode=false
    local search_mode=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e)
                edit_mode=true
                shift
                ;;
            all)
                search_mode="all"
                shift
                ;;
            most)
                search_mode="most"
                shift
                ;;
            -h|--help)
                echo "Usage: fzf-func [options] [search_mode]"
                echo "Options:"
                echo "  -e        Edit the selected function in vi"
                echo "  -h, --help  Show this help message"
                echo "Search modes:"
                echo "  (default) Only include those specfically starting with 'function'"
                echo "  all        Include all functions"
                echo "  most       exclude the underscored functions"
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Choose the appropriate pattern
    local search_pattern="$FIND_ONLY_FUNCTION"
    [[ "$search_mode" == "all" ]] && search_pattern="$FIND_FUNCTIONS"  # includes all functions
    [[ "$search_mode" == "most" ]] && search_pattern="$FIND_WITH_DASH" # excludes underscore ones, assumed to be private

    # Create a temporary preview script
    local preview_script
    preview_script=$(mktemp)

    # Write preview function to the temporary script
    cat > "$preview_script" << 'EOF'
#!/bin/bash
input="$1"
func_name=$(echo "$input" | cut -f1)
file=$(echo "$input" | cut -f2 | awk '{print $1}')
fileName=$(basename "$file")

# Display header
echo -e "\033[1;32m$func_name\033[0m in \033[1;34m$fileName\033[0m\n"

# Find line number - improved pattern matching
line_num=$(grep -n "^\s*\(function\s\+\)\?${func_name}\s*().*{" "$file" | head -1 | cut -d: -f1)

if [[ -z "$line_num" ]]; then
    # Try alternative pattern if the first one didn't work
    line_num=$(grep -n "^\s*\(function\s\+\)\?${func_name}\(\s*\|\s\+\)()" "$file" | head -1 | cut -d: -f1)
fi

if [[ -n "$line_num" ]]; then
    # Extract function body to a temporary file for syntax highlighting
    temp_func_file=$(mktemp)

    awk "
        # Start printing when we find the function
        NR == $line_num { in_func = 1 }

        # Print lines while in the function
        in_func { print }

        # Stop when we find the closing brace
        in_func && /^[[:space:]]*}/ { exit }
    " "$file" > "$temp_func_file"

    # Apply syntax highlighting if bat is available, otherwise use cat
    if command -v bat &>/dev/null; then
        bat --color=always --style=numbers --language=bash "$temp_func_file"
    elif command -v pygmentize &>/dev/null; then
        pygmentize -l bash -O style=monokai "$temp_func_file"
    else
        cat -n "$temp_func_file"
    fi

    # Clean up
    /bin/rm -f "$temp_func_file"
else
    echo "Function body not found"
fi
EOF

    # Make the preview script executable
    chmod +x "$preview_script"

    # Find and select
    local selected
    selected=$(
        grep -r --include="*.sh" -E "$search_pattern" "$SCRIPTS" 2>/dev/null |
        sed -E 's/^([^:]+):([[:space:]]*(function[[:space:]]+)?([a-zA-Z0-9_-]+)[[:space:]]*\(\).*)/\4\t\1\t\2/' |
        fzf --prompt="Select function> " \
            --height=40% \
            --delimiter="\t" \
            --with-nth=1 \
            --preview="$preview_script {}" \
            --preview-window="right:60%" \
            --bind "ctrl-/:toggle-preview" \
            --ansi \
            --header="Function Picker"
    )

    # Clean up temporary file
    /bin/rm -f "$preview_script"

    [[ -z "$selected" ]] && return

    # Extract pieces
    local function_name file
    function_name=$(echo "$selected" | cut -f1)
    file=$(echo "$selected" | cut -f2 | awk '{print $1}')

    # If -e was given, open the file in vi at function definition
    if $edit_mode; then
        local line_num
        # Improved line number detection for vi
        line_num=$(grep -n "^\s*\(function\s\+\)\?${function_name}\s*().*{" "$file" | head -1 | cut -d: -f1)
        
        # If not found, try alternative pattern
        if [[ -z "$line_num" ]]; then
            line_num=$(grep -n "^\s*\(function\s\+\)\?${function_name}\(\s*\|\s\+\)()" "$file" | head -1 | cut -d: -f1)
        fi
        
        # If still not found, try a more permissive pattern
        if [[ -z "$line_num" ]]; then
            line_num=$(grep -n "${function_name}\s*(" "$file" | head -1 | cut -d: -f1)
        fi

        [[ -n "$line_num" ]] && vi +"$line_num" "$file" || vi "$file"
    else
        # Otherwise, insert the function name into terminal input
        if [[ -n "$ZSH_VERSION" ]]; then
            print -z "$function_name"
        elif [[ -n "$BASH_VERSION" ]]; then
            READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$function_name${READLINE_LINE:$READLINE_POINT}"
            READLINE_POINT=$((READLINE_POINT + ${#function_name}))
        else
            echo "$function_name"
        fi
    fi
}

## Some options for the search
FIND_FUNCTIONS='^[[:space:]]*(function[[:space:]]+)?[a-zA-Z0-9_-]+[[:space:]]*\(\)[[:space:]]*\{'
FIND_ONLY_FUNCTION='^[[:space:]]*function[[:space:]]+[a-zA-Z0-9_-]+[[:space:]]*\(\)[[:space:]]*\{'
FIND_WITH_DASH='^[[:space:]]*(function[[:space:]]+)?[a-zA-Z0-9_-]*-[a-zA-Z0-9_-]*[[:space:]]*\(\)[[:space:]]*\{'