#!/bin/bash

mkdir -p $CI_DATA

podman run \
	-d \
	--rm \
	--name cloud-init-server \
	--privileged \
	-p $DUMMY_IP:8000:8000 \
	--expose 8000 \
	-v $CI_DATA:/data/cloud-init \
	-w /data/cloud-init \
	python:latest \
	python3 -m http.server
