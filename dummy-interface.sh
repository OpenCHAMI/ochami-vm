#!/bin/bash
modprobe dummy

ip link add d01 type dummy
ip addr add $DUMMY_IP dev d01
ip link set d01 up