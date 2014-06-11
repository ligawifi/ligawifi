#!/bin/sh
# Copyright © 2011-2014 WiFi Mesh: New Zealand Ltd.
# All rights reserved.

# Load in the settings
. /sbin/wifimesh/settings.sh

echo "WiFi Mesh Connection Checker"
echo "----------------------------------------------------------------"

# Check that we are allowed to use this
if [ "$(uci get wifimesh.ping.enabled)" -eq 0 ]; then
	echo "This script is disabled, exiting..."
	exit
fi

# Define the default status
bad_status="0"

# Deletes any bad mesh paths that may occur from time to time
iw ${if_mesh} mpath dump | grep '00:00:00:00:00:00' | while read line; do
	iw ${if_mesh} mpath del $(echo $line | awk '{ print $1 }')
done

# Tests time is accurate
if [ $( echo $(date -I) | grep '1970' ) ]; then
	ntpd -n -q -p time.wifi-mesh.co.nz > /dev/null
fi

# Tests LAN Connectivity
ping -c 2 -w 2 ${ip_gateway} > /dev/null
if [ $? -eq 0 ]; then
	lan_status=1
else
	# Try to resolve LAN issues by renewing DHCP lease
	udhcpc -i br-wan --hostname $(uci get system.@system[0].hostname) --fqdn $(uci get system.@system[0].hostname) | grep 'obtained' > /dev/null
	
	# Tests LAN Connectivity (again)
	if [ "$(ping -c 2 $(route -n | grep 'UG' | grep 'br-wan' | awk '{ print $2 }' | head -1) )" ]; then
		lan_status=1
		
		log_message "check: LAN problem, resolved by renewing DHCP lease"
	else
		bad_status=1
		lan_status=0
		
		log_message "check: LAN problem, couldn't resolve by renewing DHCP lease"
	fi
fi

# Tests WAN Connectivity
if [ "$(ping -c 2 $(uci get wifimesh.ping.server))" ]; then
	wan_status=1
	dns_status=1
else
	# Tests DNS Connectivity
	nslookup $(uci get wifimesh.ping.server) > /dev/null
	dns_temp=$?
	
	if [ "${dns_temp}" -eq 0 ]; then
		dns_status=1
	else
		# Try to resolve DNS issues by reconfiguring DNS to Google (8.8.8.8)
		rm /tmp/resolv.conf >> /dev/null
		rm /tmp/resolv.conf.auto >> /dev/null
		rm /tmp/resolv.conf.dhcp >> /dev/null
		
		echo "" > /tmp/resolv.conf
		echo "nameserver 8.8.8.8" >> /tmp/resolv.conf
		echo "nameserver 8.8.4.4" >> /tmp/resolv.conf
		
		# Tests DNS Connectivity (again)
		nslookup $(uci get wifimesh.ping.server) > /dev/null
		dns_temp=$?
		
		if [ "${dns_temp}" -eq 0 ]; then
			dns_status=1
			
			log_message "check: WAN problem, resolved by changing DNS to Google (8.8.8.8)"
		else
			bad_status=1
			dns_status=0
			
			log_message "check: WAN problem, couldn't resolve by changing DNS to Google (8.8.8.8)"
		fi
	fi
fi

# Use the LEDs
if [ "${bad_status}" -eq 1 ]; then
	if [ "$(cat /tmp/sysinfo/board_name)" = "bullet-m" ]; then
		echo 0 > /sys/class/leds/ubnt:green:link4/brightness
		echo 0 > /sys/class/leds/ubnt:green:link3/brightness
		echo 0 > /sys/class/leds/ubnt:orange:link2/brightness
		echo 0 > /sys/class/leds/ubnt:red:link1/brightness
		echo "timer" > /sys/class/leds/ubnt:red:link1/trigger
		echo 5000 > /sys/class/leds/ubnt:red:link1/delay_on
		echo 1000 > /sys/class/leds/ubnt:red:link1/delay_off
	elif [ "$(grep 'om2p' /tmp/sysinfo/board_name)" ]; then
		echo 0 > /sys/class/leds/om2p:green:wifi/brightness
		echo 0 > /sys/class/leds/om2p:yellow:wifi/brightness
		echo 0 > /sys/class/leds/om2p:red:wifi/brightness
		echo "timer" > /sys/class/leds/om2p:red:wifi/trigger
		echo 5000 > /sys/class/leds/om2p:red:wifi/delay_on
		echo 1000 > /sys/class/leds/om2p:red:wifi/delay_off
	fi
else
	if [ "$(cat /tmp/sysinfo/board_name)" = "bullet-m" ]; then
		echo "none" > /sys/class/leds/ubnt:red:link1/trigger
		echo 1 > /sys/class/leds/ubnt:green:link4/brightness
		echo 1 > /sys/class/leds/ubnt:green:link3/brightness
		echo 1 > /sys/class/leds/ubnt:orange:link2/brightness
		echo 1 > /sys/class/leds/ubnt:red:link1/brightness
	elif [ "$(grep 'om2p' /tmp/sysinfo/board_name)" ]; then
		echo "none" > /sys/class/leds/om2p:red:wifi/trigger
		echo 1 > /sys/class/leds/om2p:green:wifi/brightness
		echo 0 > /sys/class/leds/om2p:yellow:wifi/brightness
		echo 0 > /sys/class/leds/om2p:red:wifi/brightness
	fi
fi

# Log that result
log_message "check: LAN: ${lan_status} | WAN: ${wan_status} | DNS: ${dns_status}"
