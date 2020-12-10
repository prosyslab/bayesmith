#!/usr/bin/env bash

# Usage: ./run-sparrow.sh CONTAINER_NAME [ SPARROW_ARGS .. ]

DOCKER_IMAGE=$1

SPARROW_ARGS=${@:2}


CONTAINER_IMAGE=$(docker run -i --detach $DOCKER_IMAGE)
BUILD=/src/build.sh

OUT=/out/smake-out

dir=$(pwd)
PROJECT_ROOT=$(dirname "$dir")
SPARROW_BIN=$PROJECT_ROOT/sparrow/bin/sparrow

docker exec $CONTAINER_IMAGE $BUILD sparrow

docker cp $CONTAINER_IMAGE:$OUT .

docker kill $CONTAINER_IMAGE

$SPARROW_BIN $SPARROW_ARGS smake-out/*.i
