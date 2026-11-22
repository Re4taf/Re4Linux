#!/bin/sh

cd /home/container || exit 1
exec java -Xms128M -XX:MaxRAMPercentage=95.0 -jar server.jar
