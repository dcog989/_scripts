#!/bin/sh
# Artists under /mnt/data/Music that contain at least one .flac
find /mnt/data/Music -iname '*.flac' -printf '%P\n' | cut -d/ -f1 | sort -u
