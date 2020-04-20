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
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_ENDPOINT_URL"
    DR_COMPOSE_FILE="-c $DIR/docker/docker-compose.yml -c $DIR/docker/docker-compose-azure.yml"
elif [[ "${DR_CLOUD,,}" == "local" ]];
then
    export DR_LOCAL_S3_ENDPOINT_URL="http://localhost:9000"
    DR_LOCAL_PROFILE_ENDPOINT_URL="--profile $DR_LOCAL_S3_PROFILE --endpoint-url $DR_LOCAL_ENDPOINT_URL"
    DR_COMPOSE_FILE="-c $DIR/docker/docker-compose.yml -c $DIR/docker/docker-compose-local.yml"
else
    DR_LOCAL_PROFILE_ENDPOINT_URL=""
    DR_COMPOSE_FILE="-c $DIR/docker/docker-compose.yml"
fi

## Check if we have an AWS IAM assumed role, or if we need to set specific credentials.
if [ $(aws sts get-caller-identity | jq '.Arn' | awk /assumed-role/ | wc -l) -eq 0 ];
then
    export DR_LOCAL_ACCESS_KEY_ID=$(aws --profile $DR_LOCAL_S3_PROFILE configure get aws_access_key_id | xargs)
    export DR_LOCAL_SECRET_ACCESS_KEY=$(aws --profile $DR_LOCAL_S3_PROFILE configure get aws_secret_access_key | xargs)
    DR_COMPOSE_FILE="$DR_COMPOSE_FILE:$DIR/docker/docker-compose-keys.yml"
    export DR_UPLOAD_PROFILE="--profile $DR_UPLOAD_S3_PROFILE"
fi

export DR_COMPOSE_FILE
export DR_LOCAL_PROFILE_ENDPOINT_URL

function dr-upload-custom-files {
  if [[ "${DR_CLOUD,,}" == "azure" || "${DR_CLOUD,,}" == "local" ]];
  then
	  ROBOMAKER_COMMAND="" docker-compose $DR_COMPOSE_FILES up -d minio
  fi
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Uploading files to $CUSTOM_TARGET"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $DIR/custom_files/ $CUSTOM_TARGET
}

function dr-upload-model {
  dr-update-env && ${DIR}/scripts/upload/upload-model.sh "$@"
}

function dr-list-aws-models {
  dr-update-env && ${DIR}/scripts/upload/list-set-models.sh "$@"
}

function dr-set-upload-model {
  dr-update-env && ${DIR}/scripts/upload/list-set-models.sh "$@"
}

function dr-download-custom-files {
  if [[ "${DR_CLOUD,,}" == "azure" || "${DR_CLOUD,,}" == "local" ]];
  then
	  ROBOMAKER_COMMAND="" docker-compose $DR_COMPOSE_FILES up -d minio
  fi
  eval CUSTOM_TARGET=$(echo s3://$DR_LOCAL_S3_BUCKET/$DR_LOCAL_S3_CUSTOM_FILES_PREFIX/)
  echo "Downloading files from $CUSTOM_TARGET"
  aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 sync $CUSTOM_TARGET $DIR/custom_files/
}

function dr-start-training {
  dr-update-env
  bash -c "cd $DIR/scripts/training && ./start.sh $@"
}

function dr-increment-training {
  dr-update-env && ${DIR}/scripts/training/increment.sh "$@" && dr-update-env
}

function dr-stop-training {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/training && ./stop.sh"
}

function dr-start-evaluation {
  dr-update-env
  bash -c "cd $DIR/scripts/evaluation && ./start.sh"
}

function dr-stop-evaluation {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/evaluation && ./stop.sh"
}

function dr-start-loganalysis {
  ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/log-analysis && ./start.sh"
}

function dr-stop-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /loganalysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    ROBOMAKER_COMMAND="" bash -c "cd $DIR/scripts/log-analysis && ./stop.sh"
  else
    echo "Log-analysis is not running."
  fi

}

function dr-logs-sagemaker {

    STACK_NAME="deepracer-$DR_RUN_ID"
    RUN_NAME=${DR_LOCAL_S3_MODEL_PREFIX}

    SAGEMAKER_CONTAINERS=$(docker ps | awk ' /sagemaker/ { print $1 } '| xargs )

    if [[ -n $SAGEMAKER_CONTAINERS ]];
    then
        for CONTAINER in $SAGEMAKER_CONTAINERS; do
            CONTAINER_NAME=$(docker ps --format '{{.Names}}' --filter id=$CONTAINER)
            CONTAINER_PREFIX=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $1')
            COMPOSE_SERVICE_NAME=$(echo $CONTAINER_NAME | perl -n -e'/(.*)_(algo(.*))_./; print $2')
            COMPOSE_FILE=$(sudo find /tmp/sagemaker -name docker-compose.yaml -exec grep -l "$RUN_NAME" {} + | grep $CONTAINER_PREFIX)
            if [[ -n $COMPOSE_FILE ]]; then
                docker logs -f $CONTAINER
            fi
        done
    else
        echo "Sagemaker is not running."
    fi

}

function dr-logs-robomaker {
    eval ROBOMAKER_ID=$(docker ps | grep "deepracer-${DR_RUN_ID}_robomaker" | cut -f1 -d\  | head -1)
    if [ -n "$ROBOMAKER_ID" ]; then
        docker logs -f $ROBOMAKER_ID
    else
        echo "Robomaker is not running."
    fi
}

function dr-logs-loganalysis {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /loganalysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    docker logs -f $LOG_ANALYSIS_ID
  else
    echo "Log-analysis is not running."
  fi

}

function dr-loganalysis-url {
  eval LOG_ANALYSIS_ID=$(docker ps | awk ' /loganalysis/ { print $1 }')
  if [ -n "$LOG_ANALYSIS_ID" ]; then
    URL=$(docker logs $LOG_ANALYSIS_ID | perl -n -e'/(http:\/\/127\.0\.0\.1\:8888\/\?.*)/; print $1')
    echo "Log-analysis URL: $URL"
  else
    echo "Log-analysis is not running."
  fi
}

function dr-update {
   dr-update-env
}

function dr-reload {
   source $DIR/bin/activate.sh $DR_CONFIG
}


