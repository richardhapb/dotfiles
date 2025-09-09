#!/usr/bin/env bash

set -e

config_dir="~/.config/systemd/user"

mkdir -p "$config_dir"

file="$config_dir/ssh-agent.socket"
echo "Creating $file"

cat > "$file" << EOF
[Unit]
Description=SSH Agent Socket

[Socket]
ListenStream=%t/ssh-agent.socket
SocketMode=0600

[Install]
WantedBy=sockets.target
EOF

file="$config_dir/ssh-agent.service"
echo "Creating $file"

cat > "$file" << EOF
[Unit]
Description=SSH Agent
After=graphical-session-pre.target

[Service]
Type=simple
# Put socket inside a dedicated runtime dir to avoid name clashes
Environment=SSH_AUTH_SOCK=%t/ssh-agent/agent.sock
ExecStartPre=/usr/bin/rm -f %t/ssh-agent/agent.sock
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK

[Install]
WantedBy=default.target
EOF

echo "Files created successfully, enabling service"

systemctl --user enable --now ssh-agent.socket

export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

echo "ssh-agent enabled succesfully"

