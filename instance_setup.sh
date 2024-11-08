#!/bin/bash

# didn't actually launch it, so it might not work :))

sudo apt-get install git nginx golang

git clone https://github.com/shefeg/golang-demo

cd golang-demo

GOOS=linux GOARCH=amd64 go build -o golang-demo
chmod +x golang-demo
DB_ENDPOINT=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=pass123 DB_NAME=postgres ./golang-demo

sudo cat > /etc/nginx/sites-available/goapp << EOL
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL

sudo ln -s /etc/nginx/sites-available/goapp /etc/nginx/sites-enabled/

sudo systemctl restart nginx
sudo nginx -s reload
