#! /usr/bin/env bash
#
# Author: Joshua Gilman <joshuagilman@gmail.com>
#
#/ Usage: checksum.sh
#/
#/ Calculates the checksum of setup.sh and saves it to setup.sh.sha256
#/

if ! shasum -a 256 setup.sh.sha256 &>/dev/null; then
	shasum -a 256 setup.sh >setup.sh.sha256
	exit 1
fi
