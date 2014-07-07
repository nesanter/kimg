#!/bin/bash

cd $1

[ -e master_config ] || exit 1
[ -e image-main.sh ] || exit 1
