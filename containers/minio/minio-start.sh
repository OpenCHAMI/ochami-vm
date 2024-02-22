#!/bin/bash

mkdir -p $MINIO_DIR

podman run \
	-d \
	-v $MINIO_DIR:/data \
	--name minio-server \
	-p $DUMMY_IP:9000:9000 \
	-p $DUMMY_IP:9001:9001 \
	-e "MINIO_ROOT_USER=$MINIO_USER" \
	-e "MINIO_ROOT_PASSWORD=$MINIO_PASSWD" \
	minio/minio:latest \
	server /data --console-address ":9001"

podman exec minio-server bash -c " \
	mc alias set local http://localhost:9000 $MINIO_USER $MINIO_PASSWD; \
	mc mb local/efi; \
	mc mb local/boot-images; \
	mc anonymous set download local/efi; \
	mc anonymous set download local/boot-images; \
	"
