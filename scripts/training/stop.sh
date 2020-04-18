#!/usr/bin/env bash
export COMPOSE_FILE=$DR_COMPOSE_FILE
docker-compose stop rl_coach
docker-compose stop robomaker

SAGEMAKER=$(docker ps | awk ' /sagemaker/ { print $1 }')
if [[ -n $SAGEMAKER ]];
then
    docker stop $(docker ps | awk ' /sagemaker/ { print $1 }')
    docker rm $(docker ps -a | awk ' /sagemaker/ { print $1 }')
fi