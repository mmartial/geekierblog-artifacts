#!/bin/bash

timeout 25  ~/.config/conky/glances_get.sh -c -t -u https://glc-test.example.com \
    -m /rootfs:/ \
    -m /rootfs/data:data
