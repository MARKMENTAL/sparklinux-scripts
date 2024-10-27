#!/bin/ash
mkdir -pv ~/tmp
export TMPDIR=~/tmp
sh aports/scripts/mkimage.sh --tag edge \
    --outdir ~/iso \
    --arch x86_64 \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --profile virt
