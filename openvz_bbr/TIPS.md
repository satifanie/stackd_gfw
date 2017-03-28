##SHM BUG
```
Checking that ptrace can change system call numbers...OK
Checking syscall emulation patch for ptrace...OK
Checking advanced syscall emulation patch for ptrace...OK
Checking for tmpfs mount on /dev/shm...OK
Checking PROT_EXEC mmap in /dev/shm/...failed: Operation not permitted
/dev/shm/ must be not mounted noexec
/dev/shm/ is tmpfs and is mounted noexec
```
在宿主机的/etc/fstab 额外加一行如下
```
shm    /dev/shm        tmpfs    nodev,nosuid                0       0 
```

===

##UML CONFIG
```
UML-specific options 
    ==> [*] Force a static link 
Device Drivers
    ==> [*] Network device support
        ==> <*> Universal TUN/TAP device driver support
[*] Networking support
    ==> Networking options
        ==> [*] IP: TCP syncookie support
        ==> [*] TCP: advanced congestion control
            ==> <*> BBR TCP
            ==> <*> Default TCP congestion control (BBR)
        ==> [*] QoS and/or fair queueing
            ==> <*> Quick Fair Queueing scheduler (QFQ)
            ==> <*> Controlled Delay AQM (CODEL)
            ==> <*> Fair Queue Controlled Delay AQM (FQ_CODEL)
            ==> <*> Fair Queue
```

===

##REMAKE

Host
```
apt-get install build-essential libncurses5-dev bc
#resize2fs alpine_mini 1G
#screen /dev/pts/X
apt-get install e2fsprogs screen
#apt-get install kernel-package uml-utilities
dd if=/dev/zero of=alpine_mini bs=1M count=150
mkfs.ext4 -L ROOT alpine_mini
mkdir alpine
mkdir old
mount -o loop alpine_mini alpine
mount -o loop alpine_bbr_ss.img old

REL="v3.5"
REL=${REL:-edge}
MIRROR=${MIRROR:-http://nl.alpinelinux.org/alpine}
REPO=$MIRROR/$REL/main
ARCH=$(uname -m)
ROOTFS=${ROOTFS:-alpine}
APKV=`curl -s $REPO/$ARCH/APKINDEX.tar.gz | tar -Oxz | grep -a '^P:apk-tools-static$' -A1 | tail -n1 | cut -d: -f2`
mkdir tmp
curl -s $REPO/$ARCH/apk-tools-static-${APKV}.apk |	tar -xz -C tmp sbin/apk.static
tmp/sbin/apk.static --repository $REPO --update-cache --allow-untrusted --root $ROOTFS --initdb add alpine-base
printf '%s\n' $REPO > $ROOTFS/etc/apk/repositories

sed -i 's/#rc_sys.*/rc_sys="uml"/' alpine/etc/rc.conf
mkdir alpine/etc/shadowsocks-go
cp old/usr/local/bin/ss-goserver alpine/usr/local/bin
cp old/etc/shadowsocks-go/config.json alpine/etc/shadowsocks-go 
cp old/etc/fstab alpine/etc 
cp old/etc/sysctl.conf alpine/etc 
cp old/etc/hostname alpine/etc/    
cp old/etc/hosts alpine/etc 
cp old/etc/resolv.conf alpine/etc 
cp old/etc/local.d/liyangyijie.start alpine/etc/local.d
cp old/etc/network/interfaces alpine/etc/network
cp old/etc/inittab alpine/etc

bash
nohup ./vmlinux ubda=alpine_mini rw eth0=tuntap,tap0 mem=64m &
tail -n10 nohup.out
#pidof vmlinux|xargs kill
```

NET.SH
```
D_I=`ip route show 0/0 | sort -k 7 | head -n 1 | sed -n 's/^default.* dev \([^ ]*\).*/\1/p'`
sudo ip tuntap add tap0 mode tap 
sudo ip addr add 10.0.0.1/24 dev tap0 
sudo ip link set tap0 up 
sudo iptables -P FORWARD ACCEPT
sudo iptables -t nat -A POSTROUTING -o ${D_I} -j MASQUERADE
sudo iptables -t nat -A PREROUTING -i ${D_I} -p tcp --dport 443 -j DNAT --to-destination 10.0.0.2
sudo iptables -t nat -A PREROUTING -i ${D_I} -p tcp --dport 9000:19000 -j DNAT --to-destination 10.0.0.2
```

UML
```
apk update
rc-update add local default
#setup-alpine
#/bin/dd if=/dev/zero of=/swapfile bs=1M count=64

cat /etc/local.d/liyangyijie.start 
#!/bin/sh
#make swap
/bin/chmod 600 /swapfile
/sbin/mkswap /swapfile
/sbin/swapon /swapfile
#fix net
sleep 3
/etc/init.d/networking restart
#start ss
/usr/bin/nohup /usr/local/bin/ss-goserver -c /etc/shadowsocks-go/config.json > /dev/null 2>&1 &

cat /etc/fstab
# 
# /etc/fstab: static file system information
#
# <file system>	<dir>	<type>	<options>	<dump>	<pass>
LABEL=ROOT	/	auto	defaults	1	1

cat /etc/network/interfaces
auto lo
  iface lo inet loopback

auto eth0
  iface eth0 inet static
   address 10.0.0.2
   gateway 10.0.0.1
   netmask 255.255.255.0

cat /etc/sysctl.conf
# max open files
fs.file-max = 51200
# max read buffer
net.core.rmem_max = 67108864
# max write buffer
net.core.wmem_max = 67108864
# default read buffer
net.core.rmem_default = 65536
# default write buffer
net.core.wmem_default = 65536
# max processor input queue
net.core.netdev_max_backlog = 4096
# max backlog
net.core.somaxconn = 4096
# resist SYN flood attacks
net.ipv4.tcp_syncookies = 1
# reuse timewait sockets when safe
net.ipv4.tcp_tw_reuse = 1
# turn off fast timewait sockets recycling
net.ipv4.tcp_tw_recycle = 0
# short FIN timeout
net.ipv4.tcp_fin_timeout = 30
# short keepalive time
net.ipv4.tcp_keepalive_time = 1200
# outbound port range
net.ipv4.ip_local_port_range = 10000 65000
# max SYN backlog
net.ipv4.tcp_max_syn_backlog = 4096
# max timewait sockets held by system simultaneously
net.ipv4.tcp_max_tw_buckets = 5000
# turn on TCP Fast Open on both client and server side
net.ipv4.tcp_fastopen = 3
# TCP receive buffer
net.ipv4.tcp_rmem = 4096 87380 67108864
# TCP write buffer
net.ipv4.tcp_wmem = 4096 65536 67108864
# turn on path MTU discovery
net.ipv4.tcp_mtu_probing = 1
#BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

#关机
halt
#重启
reboot

```

===

## SLiRP
TUN/TAP are just not available for some reason.No iptables.No NAT.
Use SLiRP.
```
apt-get install slirp
```
/usr/bin/slirp is too slow,use /usr/bin/slirp-fullbolt.
Redirect inside port to outside port,slirp-fullbolt -S "redir 8042 80", in8042 bindto out80.
But you had to edit  ~/.slirprc,if you want to use it on UML.
```
redir 9988 9988
redir 9000 9000
.... 
```
And
```
nohup ./vmlinux root=/dev/ubda ubd0=alpine_bbr_ss_swap.img rw eth0=slirp,,/usr/bin/slirp-fullbolt mem=64m &

```
ICMP traffic (ping) from guest to the internet is not supported.
You could ping your vps'pub ip to test your net.
you may up net by
```
ifconfig eth0 down
ifconfig eth0 10.0.2.15 up
route add default gw 10.0.2.15
ping xx.xx.xx.xx
```
or edit /etc/network/interfaces
```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
        address 10.0.2.15
        netmask 255.255.255.255
        gateway 10.0.2.15

```
Then
```
ifconfig eth0 down
/etc/init.d/networking restart
ping xx.xx.xx.xx
```

===

## Host file access
Just cmd in UML
```shell
mount none /mnt/home -t hostfs -o /home/uml
```
Or edit fstab in UML
```shell
cat /etc/fstab
# 
# /etc/fstab: static file system information
#
# <file system>	<dir>	<type>	<options>	<dump>	<pass>
LABEL=ROOT	/		auto	defaults	1	1
none		/mnt/home	hostfs	defaults	1	1
```
In host 
```shell
mkdir /home/uml
```
Then 
```shell
nohup ./vmlinux ubda=alpine_mini rw hostfs=/home/uml eth0=tuntap,tap0 mem=64m &
```