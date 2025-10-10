#!/bin/bash
#File location on Pi: /home/chungy/poweron.sh

set -u
# 2s pulse, then 5s hard pull-down (timeout returns 124, which we ignore)
gpioset --mode=time --sec=2 --bias=pull-down $(gpiofind GPIO27)=1
timeout 5 gpioset --mode=signal gpiochip0 27=0 || true
exit 0