#!/usr/bin/env bash

password=$1
port=$2

if [ -z password ]; then
    echo "Password is required, pass the password as an argument"
    exit 1
fi

if [ -z port ]; then
    port=5440
fi

volume="postgres_data"

if [[ "$OSTYPE" == "darwin"* ]]; then
    volume=$(fd -I --type file postgresql.conf /opt/homebrew/var | tail -n 1 | sed -E 's/\/postgresql.conf$//')
fi

docker run -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD="$(password)" -v "$volume":/var/lib/postgresql/data --name postgres -p "$port":5432 -d postgres

echo "Container running succesfully, listening on port $port"

