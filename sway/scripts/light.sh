#!/bin/sh
CONTENT=$(curl --retry 3 --retry-all-errors --retry-delay 3 -s http://ip-api.com/json/)
longitude=$(echo $CONTENT | jq .lon)
latitude=$(echo $CONTENT | jq .lat)
wlsunset -l $latitude -L $longitude
