#!/usr/bin/env bash

DOWNLOAD_URL="https://discord.com/api/download/stable?platform=linux&format=tar.gz"
TMP_PATH="/tmp/Discord/"
TMP_FILE="Discord.tar.gz"
INSTALL_PATH="/opt/Discord/"

# Check if root
if [ $(id -u) -ne 0 ]; then
    echo "Script must be run as root"
    exit 1
fi

# Download discord zip
curl -L -o "$TMP_FILE" --skip-existing --create-dirs \
    --output-dir "$TMP_PATH" "$DOWNLOAD_URL" 

# Kill Discord processes
for PID in $(pgrep Discord); do
    kill -9 $PID
    echo "Killed Discord process with PID $PID"
done

# Delete existing content at installation dir
for file in `ls -a $INSTALL_PATH`; do
    # echo "File is $file"
    if [[ "$file" = "." || "$file" = ".." ]]; then 
        # echo "Skipping file $file"
        continue 
    fi 

    # echo $file    
    echo "Deleting $file .." 
    rm -rd $INSTALL_PATH$file
done

tar -xzvf "$TMP_PATH$TMP_FILE" -C "$INSTALL_PATH" --strip-components=1

echo "All done!"
