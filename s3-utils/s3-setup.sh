#!/bin/bash
export S3_URL=http://$DUMMY_IP:9000
export S3_ACCESS=$S3_ACCESS
export S3_SECRET=$S3_SECRET
export PATH=$PATH:$(readlink -f $(dirname ${BASH_SOURCE[0]})/bin)
