#!/bin/bash
function dr-update-env {

  if [[ -f "$DIR/system.env" ]]
  then
    LINES=$(grep -v '^#' $DIR/system.env)
    for l in $LINES; do
      env_var=$(echo $l | cut -f1 -d\=)
      env_val=$(echo $l | cut -f2 -d\=)
      eval "export $env_var=$env_val"
    done
  else
    echo "File system.env does not exist."
    exit 1
  fi

  if [[ -f "$DR_CONFIG" ]]
  then
    LINES=$(grep -v '^#' $DR_CONFIG)
    for l in $LINES; do
      env_var=$(echo $l | cut -f1 -d\=)
      env_val=$(echo $l | cut -f2 -d\=)
      eval "export $env_var=$env_val"
    done
  else
    echo "File run.env does not exist."
    exit 1
  fi

  if [[ -z "${DR_RUN_ID}" ]]; then
    export DR_RUN_ID=0
  fi
  export DR_ROBOMAKER_PORT=$(echo "8080 + $DR_RUN_ID" | bc)

}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIR="$( dirname $SCRIPT_DIR )"
export DR_DIR=$DIR

if [[ -f "$1" ]];
then
  export DR_CONFIG=$(readlink -f $1)
  dr-update-env
elif [[ -f "$DIR/run.env" ]];
then
  export DR_CONFIG="$DIR/run.env"
  dr-update-env
else
  echo "No configuration file."
  exit 1
fi

if [[ "${DR_CLOUD,,}" == "azure" ]];
then
    export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
    DR_COMPOSE_FILE="-c $DIR/docker/docker-compose.yml -c $DIR/docker/docker-compose-endpoint.yml"
    DR_MINIO_COMPOSE_FILE="-c $DIR/docker/docker-compose-azure.yml"
elif [[ "${DR_CLOUD,,}" == "local" ]];
then
    export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_S3_ENDPOINT_URL"
    DR_COMPOSE_FILE="-c $DIR/docker/docker-compose.yml -c $DIR/docker/docker-compose-endpoint.yml"
    DR_MINIO_COMPOSE_FILE="-c $DIR/docker/docker-compose-local.yml"
else
    DR_LOCAL_PROFILE_ENDPOINT_URL=""
    DR_COMPOSE_FILE="-c $DIR/docker/docker-compose.yml"
fi

## Check if we have an AWS IAM assumed role, or if we need to set specific credentials.
if [ $(aws sts get-caller-identity | jq '.Arn' | awk /assumed-role/ | wc -l) -eq 0 ];
then
    export DR_LOCAL_ACCESS_KEY_ID=$(aws --profile $DR_LOCAL_S3_PROFILE configure get aws_access_key_id | xargs)
    export DR_LOCAL_SECRET_ACCESS_KEY=$(aws --profile $DR_LOCAL_S3_PROFILE configure get aws_secret_access_key | xargs)
    DR_COMPOSE_FILE="$DR_COMPOSE_FILE -c $DIR/docker/docker-compose-keys.yml"
    export DR_UPLOAD_PROFILE="--profile $DR_UPLOAD_S3_PROFILE"
fi

export DR_COMPOSE_FILE
export DR_LOCAL_PROFILE_ENDPOINT_URL

if [[ -n "${DR_MINIO_COMPOSE_FILE}" ]]; then
    docker stack deploy $DR_MINIO_COMPOSE_FILE s3
fi

source $SCRIPT_DIR/scripts_wrapper.sh

function dr-update {
   dr-update-env
}

function dr-reload {
   source $DIR/bin/activate.sh $DR_CONFIG
}
