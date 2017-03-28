#!/bin/sh
export HOME=/root
start(){
ip tuntap add tap0 mode tap
ip addr add 10.0.0.1/24 dev tap0
ip link set tap0 up

echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -P FORWARD ACCEPT
iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
iptables -t nat -A PREROUTING -i venet0 -p tcp --dport 30022 -j DNAT --to-destination 10.0.0.2
iptables -t nat -A PREROUTING -i venet0 -p tcp --dport 8989 -j DNAT --to-destination 10.0.0.2
iptables -t nat -A PREROUTING -i venet0 -p udp --dport 8989 -j DNAT --to-destination 10.0.0.2

screen -dmS uml /data/openvz-bbr/vmlinux root=/dev/ubda ubd0=/data/openvz-bbr/alpine_mini rw eth0=tuntap,tap0 mem=64m

}
stop(){
    kill $( ps aux | grep vmlinux )
ifconfig tap1 down
}
status(){
screen -r $(screen -list | grep uml | awk 'NR==1{print $1}')

}
action=$1
#[ -z $1 ] && action=status
case "$action" in
'start')
    start
    ;;
'stop')
    stop
    ;;
'status')
    status
    ;;
'restart')
    stop
    start
    ;;
*)
    echo "Usage: $0 { start | stop | restart | status }"
    ;;
esac
exit
