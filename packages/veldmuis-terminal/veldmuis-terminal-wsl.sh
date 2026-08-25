#!/usr/bin/env bash

if [[ $- == *i* ]] && [[ ${EUID:-0} -ne 0 ]] && [[ -r /proc/sys/kernel/osrelease ]] &&
    /usr/bin/grep -qi microsoft /proc/sys/kernel/osrelease; then
  /usr/lib/veldmuis/veldmuis-user-defaults-update --seed >/dev/null 2>&1 &
fi
