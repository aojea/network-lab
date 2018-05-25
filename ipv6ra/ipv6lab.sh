#!/bin/bash

set -x

create_ns () {
    NAMESPACE=$1
    OUT_INTERFACE=${NAMESPACE}out
    IN_INTERFACE=${NAMESPACE}in

    ip netns add $NAMESPACE
    ip link add name $OUT_INTERFACE type veth peer name $IN_INTERFACE
    ip link set netns $NAMESPACE dev $IN_INTERFACE
    ip link set up $OUT_INTERFACE
    ip netns exec $NAMESPACE ip link set up dev lo
    ip netns exec $NAMESPACE ip link set up dev $IN_INTERFACE
}


start () {
    # Create topology 2 router + 1 host in the same LAN
    ip link add name br_ipv6 type bridge
    ip link set br_ipv6 up

    for i in R1 R2 H1; do
        create_ns "$i"
        ip link set "$i"out up
        ip link set "$i"out master br_ipv6
    done

    # Configure addresses in the namespaces
    ip netns exec R1 ip -6 addr add 2001:1:1::1/64 dev R1in
    ip netns exec R1 ip -6 addr add 1:1:1::1/128 dev lo

    ip netns exec R2 ip -6 addr add 2001:1:1::2/64 dev R2in
    ip netns exec R2 ip -6 addr add 2:2:2::2/128 dev lo

    ip netns exec H1 ip -6 addr add 2001:1:1::100/64 dev H1in

    # Accept RA and announced routes
    ip netns exec H1 sysctl -w net.ipv6.conf.all.accept_ra_rt_info_max_plen=128
    ip netns exec H1 sysctl -w net.ipv6.conf.all.accept_ra=2

    # Setup radvd to announce the default route with different preference
    ip netns exec R1 radvd -C R1.conf -p /tmp/R1.pid
    ip netns exec R2 radvd -C R2.conf -p /tmp/R2.pid

    # print route table
    sleep 5

    for i in R1 R2 H1; do
        echo "$i routing table"
        ip netns exec $i ip -6 route
        echo
    done

    # Ping loopbacks of R1 and R2 to check what's route takes preference
    ip netns exec H1 ping6 -c 1 1:1:1::1 # R1 loopback
    ip netns exec H1 ping6 -c 1 2:2:2::2 # R2 loopback

}

stop () {

    for i in R1 R2 H1; do
        ip netns del $i
    done

    ip link del br_ipv6
    killall radvd
}

case "$1" in 
    start)   start ;;
    stop)    stop ;;
    *) echo "usage: $0 start|stop" >&2
       exit 1
       ;;
esac
