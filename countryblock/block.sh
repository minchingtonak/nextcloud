#!/usr/bin/env bash

# countryblock script for docker
# <scriptname> start will set up nftables and download the specified country ipsets and wait
# until it receives a INT, TERM, or KILL signal, at which time it will clean up nftables
# <scriptname> update will update the ipsets, good for a cron job
# Copyright (C) 2020 Bradford Law
# Licensed under the terms of MIT

DEFAULT_LOG=/var/log/block.log
LOG=$COUNTRYBLOCK_LOG

if [ -z $COUNTRYBLOCK_LOG ]; then
    LOG=$DEFAULT_LOG
fi

CHAIN=countryblock

# The list of country codes is provided as an environment variable or below
# COUNTRIES=

printf "Starting blocklist and ipset construction for countries: %b\n" "$COUNTRIES" >> $LOG

setup() {
	# Create table and chain
	nft add table ip filter
	nft add chain ip filter $CHAIN { type filter hook forward priority 0 \; }

	for country in $COUNTRIES; do
		COUNTRY_LOWER=${country,,}

		# Create set for each country
		nft add set ip filter $COUNTRY_LOWER { type ipv4_addr \; }

		# Create firewall rule for each country
		nft add rule ip filter $CHAIN ip saddr @$COUNTRY_LOWER drop
	done
	printf "Created %b chain and rules and sets for countries %b\n" "$CHAIN" "$COUNTRIES" >> $LOG
}

cleanup() {
	# Clean up rules and sets
	for country in $COUNTRIES; do
		COUNTRY_LOWER=${country,,}
		nft delete rule ip filter $CHAIN ip saddr @$COUNTRY_LOWER drop
		nft delete set ip filter $COUNTRY_LOWER
	done

	# Remove chain and table
	nft delete chain ip filter $CHAIN
	nft delete table ip filter

	printf "Removed %b chain and rules and sets\n" "$CHAIN"
}

update() {
	# For each country, download a list of subnets and add to its respective set
	for country in $COUNTRIES; do
		COUNTRY_LOWER=${country,,}

		# Pull the latest IP set for country
		ZONEFILE=$COUNTRY_LOWER-aggregated.zone
		wget --no-check-certificate -N https://www.ipdeny.com/ipblocks/data/aggregated/$ZONEFILE
		printf "Downloaded zone file for %b\n" "$country" >> $LOG

		# Add each IP address from the downloaded list into the set
		for i in $(cat $ZONEFILE ); do nft add element ip filter $COUNTRY_LOWER { $i \; } ; done
		printf "Added %b subnets to %b set\n" "$(wc -l $ZONEFILE)" "$country" >> $LOG
	done
}

if [ "$1" == "start" ]; then
	# Clean up old rules if they exist in case last run crashed
	cleanup
	setup
	update

	# Sleep indefinitely waiting for SIGTERM
	trap "cleanup && exit 0" SIGINT SIGTERM SIGKILL
	printf "$0: waiting for SIGINT SIGTERM or SIGKILL to clean up" >> $LOG
	sleep inf &
	wait

elif [ "$1" == "update" ]; then
	# Update the sets and exit
	update
fi
