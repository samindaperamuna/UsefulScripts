#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

WATCH_FILE="$SCRIPT_DIR/resources"
OUT_FILE="$SCRIPT_DIR/auto_copy.log"
EVENTS="modify,attrib,move,move_self,create,delete,delete_self"
TARGET_DIR="$SCRIPT_DIR/../target/classes"
MAIN_RES_DIR_PATTERN="src/main/resources"
PROCESS_DELAY=60
TMP_DIR=/tmp/auto_copy
PRE_PROCESS_FIFO=$TMP_DIR/pre_process_queue.fifo
FILES_TO_PROCESS=$TMP_DIR/files_to_process
FILES_TO_PROCESS_LOCK=$TMP_DIR/files_to_process.lock

# Usage message
MSG=$(cat <<EOF
Usage: $0 [-option] 
    Watch the files and directories provided in file $(basename "$WATCH_FILE") for changes \
and copy changes into the target directory.
        
        Options:
        -l --log        Enables logging to a file $(basename "$OUT_FILE").

        Debug options:
        -d --debug      Prints debug data.
EOF
)

declare hasLog=false
declare isDebug=false
declare -ag bgProcIds

# Initialize the FIFO, delete existing one
rm -r "$TMP_DIR" > /dev/null 2>&1
mkdir -p "$TMP_DIR" 
mkfifo "$PRE_PROCESS_FIFO"

# Trap for continuous background processes
trap 'kill "${bgProcIds[@]}"' INT TERM EXIT

# Create a trap which removes the TMP_DIR on current shell exit
# Ctrl+C included.
trap 'rm -frd "$TMP_DIR"; exit' INT TERM EXIT

# Create file containing files to process
: > "$FILES_TO_PROCESS"

# Functions to manipulate file backed list

# Get list size
size_of_process_queue() {
    (
        flock -x 200
        wc -l < "$FILES_TO_PROCESS"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Add to process list
add_to_process_queue() {
    value=$1

    if [[ -z "$value" ]]; then
        debug "Can't queue empty value"
        return 1
    fi

    (
        flock -x 200
        echo "$1" >> "$FILES_TO_PROCESS"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Remove from the list
remove_from_queue() {
    (
        flock -x 200

        # Get the next value in the queue
        local value
        value=$(sed -n '1p' "$FILES_TO_PROCESS")

        # Remove that value from the queue
        sed -i '1d' "$FILES_TO_PROCESS"

        printf '%s' "$value"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Remove at index (Zero based index)
remove_at_index_from_queue() {
    idx=$1

    # If index is out of bounds of the list, then return
    if [[ "$idx" -lt 0 || "$idx" -gt $(( $(size_of_process_queue) - 1 )) ]]; then
        debug "Index is out of bounds at: $idx of list size: $(size_of_process_queue)"
        return 1
    fi

    (
        flock -x 200

        # Get the value at the index. Sed index starts at 1.
        local value
        value=$(sed -n "$(( idx + 1 ))p" "$FILES_TO_PROCESS")

        # Remove that value from the queue
        sed -i "$(( idx  + 1 ))d" "$FILES_TO_PROCESS"

        printf '%s' "$value"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Peek into next value
peek_queue() {
    (
        flock -x 200

        # Get the next value in the queue
        local value
        value=$(sed -n '1p' "$FILES_TO_PROCESS")

        printf '%s' "$value"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Returns 0 if exists
# Prints index if exists
is_in_process_queue() {
    (
        flock -x 200

        local query=$1 line
        line=$(grep -nx -- "$query" "$FILES_TO_PROCESS" | head -n 1) || return 1

        printf '%d' "$(( ${line%%:*} - 1 ))"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Empty the list
empty_process_queue() {
    (
        flock -x 200
        : > "$FILES_TO_PROCESS"
    ) 200>"$FILES_TO_PROCESS_LOCK"
}

# Print the current list
print_process_queue() {
    local first=1

    printf "[ "

    while IFS= read -r item; do
        # Run the second command if first one fails
        [ "$first" == 1 ] || printf ' '

        printf '"%s"' "$item"
        first=0
    done < "${FILES_TO_PROCESS}"

    printf " ]\n"
}

# Prints to standard out and to the log file if logging is enabled
# Prints a new line character at the end if the second argument is not 0.
print() {
    msg=$1
    [[ -z "$2" || "$2" -ne 0 ]] && msg="$msg\n"

    # Ignore capture when used inside a function
    # by redirecting to /dev/tty
    if $hasLog; then
        echo -e "$msg" | tee -a "$OUT_FILE" > /dev/tty
    else
        echo -e "$msg" > /dev/tty
    fi
}

# Terminate script with a message
die() {
    echo -e "${2:-$MSG}"
    exit "${1:-0}"
}

# Prints a debug message if debug is enabled
debug() {
    [ $# -lt 1 ] && return 0 

    if $isDebug; then
        timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        caller="${FUNCNAME[1]}"
        if [ -n "$caller" ]; then
            caller="caller: $caller "
        fi
        print "DEBUG-$timestamp: $caller $1" 0
    fi
}

# Deduce the output path including the parent directories 
# that needs to be recreated
deduce_target_path() {
    file_path=$1

    # If standard maven resource file
    if [[ $file_path == *"$MAIN_RES_DIR_PATTERN"* ]]; then
        # Strip the filename
        file_path=$(dirname "$file_path")
        debug "Path without filename: $file_path" 

        # Deduce the internal path
        target_path="${file_path#*"$MAIN_RES_DIR_PATTERN"}"
        debug "Target path: $target_path"

        echo "$target_path" 

        return 0
    fi

    return 1
}

# Periodically process the FILES_TO_PROCESS
# Run as a background task
process() {
    while true; do
        file=$(peek_queue)
        # Ignore on empty file or empty line
        [[ -z "$file" ]] && continue

        debug "Current processing file: $file"

        file_basename=$(basename "$file");
        debug "File basename: $file_basename"

        adjusted_target_dir="$TARGET_DIR$(deduce_target_path "$file")"
        debug "Adjusted target dir: $adjusted_target_dir"

        adjusted_target="$adjusted_target_dir/$file_basename"
        debug "Adjusted target: $adjusted_target"

        print "Resource $file changed. Copying resource to $adjusted_target" 0
        res=$(mkdir -p "$adjusted_target_dir" && cp "$file" --recursive --verbose \
            "$adjusted_target_dir")
        print "$res" 0

        # No need to print the result
        remove_from_queue >/dev/null 2>&1
        debug "Current queue: [ $(print_process_queue) ]"

        sleep "$PROCESS_DELAY"
    done
}

# Move entries from the PRE_PROCESS_FIFO into FILES_TO_PROCESS
preprocess() {
    while true; do
        while IFS= read -r file; do
            ret=$(is_in_process_queue "$file")
            debug "Return value from is_in_process_queue(): $ret"

            size=$(size_of_process_queue)
            if [[ ret -ge 0 && ret -lt size ]]; then
                # If the only item do nothing
                if [[ size -eq 1 || ret -eq $(( size - 1 )) ]]; then
                    debug "Either the only or last item in queue. Doing nothing."
                    continue
                fi

                remove_at_index_from_queue "$ret" >/dev/null 2>&1
                debug "File $file removed from process queue"
                add_to_process_queue "$file"
                debug "File $file added to process queue"
            elif [[ "$ret" -eq -1 ]]; then
                add_to_process_queue "$file"
                debug "File $file added to process queue"
            else
                debug "Return index $idx cannot be processed"
            fi
        done < "$PRE_PROCESS_FIFO"
    done
}

# Check if a specific file is in the processed_files array
is_processed() {
    local -n processed_files_list=$1
    local current_file=$2
    local processed=1

    debug "processed_files_list: [ $processed_files_list ]"
    debug "current_file: $current_file"

    for filename in $processed_files_list; do
        debug "filename: $filename"

        if [[  $filename == "$current_file" ]]; then
            processed=0
            break
        fi
    done

    debug "processed: $processed"

    return $processed
}

# Validate flags
while getopts ":ldh" flag
do
    case "$flag" in
        l) hasLog=true;;
        d) isDebug=true;;
        h) die 0;;
        \?) die 1 "Invalid option: -${OPTARG}\n\n$MSG";;
    esac
done

# Shift positional parameters by 
shift $(($OPTIND - 1))

debug "Current argument index $OPTIND"
debug "Current positional argument $1"

[ $# -gt 0 ] && die 1 "Invalid argument(s): $*"

declare -a files_to_watch

# Resolve paths inside the WATCH_FILE
while IFS= read -r line; do
    debug "Current read line: $line"
    files_to_watch+=("$(realpath "$SCRIPT_DIR/$line")")
done < "$WATCH_FILE"

debug "Files to watch: [ ${files_to_watch[*]} ]"

# Run periodical background jobs
preprocess &
procId="$!"
bgProcIds+=("$procId")
debug "Background process with id: $procId added to bgProcIds"

process &
procId="$!"
bgProcIds+=("$procId")
debug "Background process with id: $procId added to bgProcIds"

# Main logic using inotifywait adds the filtered files 
# into the pre-process queue
inotifywait --monitor --quiet --recursive --event $EVENTS --format "%w%f" \
    "${files_to_watch[@]}" | while read -r file 
do
    # Convert relative path to absolute
    file=$(realpath "$file")
    file_basename=$(basename "$file");

    if [[ -f $file && $file_basename != *'~'* && $file_basename != '.'* ]]; then
        debug "Adding $file to pre-process queue"
        echo "$file" > "$PRE_PROCESS_FIFO"
    fi
done
