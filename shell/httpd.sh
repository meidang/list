#!/bin/sh

mkdir -p /data/httpd
cd /data/httpd
echo > docker-compose.yml
cat >> docker-compose.yml << EOF
version: "3.5"

services:
    httpd:
        container_name: httpd
        image: httpd
#        build:
#              dockerfile: Dockerfile
#              context: ./
        volumes:
            - "./data/:/usr/local/apache2/htdocs/"
        ports:
            - "88:80"
        restart: always
        privileged: true
EOF

docker-compose up -d

