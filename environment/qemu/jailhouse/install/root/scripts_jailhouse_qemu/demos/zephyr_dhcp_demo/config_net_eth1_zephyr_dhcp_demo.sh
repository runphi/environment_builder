#!/bin/bash

# Parametri
INTERFACE=${1:-eth1} # This NIC is an IVSHMEM linked to the non-root cell
IP_ADDRESS=${2:-192.0.2.1/24} # TODO: make this IP address as a param
DHCP_CONF=${3:-/etc/dhcp/dhcpd.conf}
DHCP_LEASES=${4:-/var/lib/dhcp/dhcpd.leases}

# check if eth1 exists 
ip addr show dev eth1 > /dev/null 2>&1
if [ $? -ne 0 ]; then

	echo "WARNING! eth1 NIC does not exits. Consider to start Jailhouse before and the root cell that creates eth1 (virtual - IVSHMEM) NIC!!!!"
	exit 255
fi

# Portare giù l'interfaccia
echo "Bringing down interface $INTERFACE..."
ip link set dev $INTERFACE down

# Configurazione dell'indirizzo IP sull'interfaccia
echo "Configuring IP address $IP_ADDRESS on $INTERFACE..."
ip addr add $IP_ADDRESS dev $INTERFACE

# Portare su l'interfaccia
echo "Bringing up interface $INTERFACE..."
ip link set dev $INTERFACE up

# Avviare il server DHCP
echo "Starting DHCP server on $INTERFACE..."
# dhcpd exits if its lease database does not exist: /var/lib/dhcp is in the
# tmpfs /tmp, and no init script creates the file at boot (/etc/default/dhcpd)
mkdir -p "$(dirname "$DHCP_LEASES")"
touch "$DHCP_LEASES"
dhcpd -d -4 -cf $DHCP_CONF -lf $DHCP_LEASES $INTERFACE &

# Configurazione delle regole di NAT con iptables
echo "Flush old eth0<->eth1 rules..."
iptables -D FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -D FORWARD -i eth0 -o eth1 -j ACCEPT

echo "Adding forwarding iptables rule from eth0<->eth1..."
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -j ACCEPT

# Enable ipv4 forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
