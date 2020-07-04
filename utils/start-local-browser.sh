#!/usr/bin/env bash

# Stream definition
TOPIC="/racecar/deepracer/kvs_stream"
WIDTH=480
HEIGHT=360
QUALITY=75

FILE=$DR_DIR/tmp/streams-$DR_RUN_ID.html
rm -f $FILE

# Check if we will use Docker Swarm or Docker Compose
if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  echo "This script does not support swarm mode."
  exit
fi

echo "<html><head><title>DR-$DR_RUN_ID - $DR_LOCAL_S3_MODEL_PREFIX - $TOPIC</title></head><body><h1>DR-$DR_RUN_ID - $DR_LOCAL_S3_MODEL_PREFIX - $TOPIC</h1>" | tee -a $FILE

ROBOMAKER_CONTAINERS=$(docker ps --format "{{.ID}}" --filter name=deepracer-$DR_RUN_ID --filter "ancestor=awsdeepracercommunity/deepracer-robomaker:$DR_ROBOMAKER_IMAGE")
for c in $ROBOMAKER_CONTAINERS; do
    C_PORT=$(docker inspect $c | jq -r '.[0].NetworkSettings.Ports["8080/tcp"][0].HostPort')
    C_URL="http://localhost:${C_PORT}/stream?topic=${TOPIC}&quality=${QUALITY}&width=${WIDTH}&height=${HEIGHT}"
    C_IMG="<img src=\"${C_URL}\"></img>"
    echo $C_IMG | tee -a $FILE
done

echo "</body></html>" | tee -a $FILE

firefox --new-tab `readlink -f $FILE ` &