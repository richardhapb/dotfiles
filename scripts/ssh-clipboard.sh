#!/usr/bin/env bash

set -e

if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_CMD="sed '' -i"

    copy_launch='<?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
         <key>Label</key>
         <string>localhost.pbcopy</string>
         <key>ProgramArguments</key>
         <array>
             <string>/usr/bin/pbcopy</string>
         </array>
         <key>inetdCompatibility</key>
         <dict>
              <key>Wait</key>
              <false/>
         </dict>
         <key>Sockets</key>
         <dict>
              <key>Listeners</key>
                   <dict>
                        <key>SockServiceName</key>
                        <string>2224</string>
                        <key>SockNodeName</key>
                        <string>127.0.0.1</string>
                   </dict>
         </dict>
    </dict>
    </plist>
    '

    paste_launch="${copy_launch//pbcopy/pbpaste}"
    paste_launch="${paste_launch//2224/2225}"

    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "$HOME/Library/LaunchAgents"

    echo "$copy_launch" > "$HOME/Library/LaunchAgents/localhost.pbcopy.plist"
    echo "$paste_launch" > "$HOME/Library/LaunchAgents/localhost.pbpaste.plist"

    # Load the launchd services
    launchctl load -w "$HOME/Library/LaunchAgents/localhost.pbcopy.plist"
    launchctl load -w "$HOME/Library/LaunchAgents/localhost.pbpaste.plist"

elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    SED_CMD="sed -i"

    if ! command -v nc >/dev/null 2>&1; then
        sudo apt update
        sudo apt install netcat-openbsd socat
    fi

    mkdir -p "$HOME/.local/share/clipboard/data"

    copy_systemd="
    [Unit]
    Description=Clipboard Copy Service
    After=network.target

    [Service]
    ExecStart=/usr/bin/socat TCP4-LISTEN:2224,fork,bind=127.0.0.1,reuseaddr SYSTEM:"cat > $HOME/.local/share/clipboard/data"
    Restart=always
    RestartSec=3
    User=$(whoami)

    [Install]
    WantedBy=multi-user.target
    "
    paste_systemd=$(echo "$copy_systemd" | sed 's/2224/2225/g' | sed 's/>//g' | sed 's/Copy/Paste/g' )

    sudo tee /etc/systemd/system/clipboard-copy.service > /dev/null <<< "$copy_systemd"
    sudo tee /etc/systemd/system/clipboard-paste.service > /dev/null <<< "$paste_systemd"

    sudo systemctl enable clipboard-copy.service
    sudo systemctl start clipboard-copy.service
    sudo systemctl enable clipboard-paste.service
    sudo systemctl start clipboard-paste.service

fi

ssh_file="$HOME/.ssh/config"
mkdir -p "$(dirname "$ssh_file")"
touch "$ssh_file"

copy_fwd="RemoteForward 2224 127.0.0.1:2224"
paste_fwd="RemoteForward 2225 127.0.0.1:2225"

$SED_CMD "s#${copy_fwd}##g" "$ssh_file"
$SED_CMD "s#${paste_fwd}##g" "$ssh_file"

printf '%s\n%s\n' "$paste_fwd" "$(cat $ssh_file)" > "$ssh_file"
printf '%s\n%s\n' "$copy_fwd" "$(cat $ssh_file)" > "$ssh_file"


