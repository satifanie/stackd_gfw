OpenVZ下开启BBR拥塞控制

作者：liyangyijie / 时间：February 28, 2017 /分类：技术小记 / 标签：none /阅览次数：580

在OpenVZ（须TUN/TAP支持）环境中通过UML（User Mode Linux）开启BBR。

##1，制作Alpine Linux镜像

在KVM的Debian 8上制作需要使用的镜像。

关于Alpine Linux，详情查看其官网。

首先写一个ext4格式的空镜像，打上ROOT的标签，方便写fstab。然后挂载到alpine目录下

dd if=/dev/zero of=alpine_mini bs=1M count=150
mkfs.ext4 -L ROOT alpine_mini
mkdir alpine
mount -o loop alpine_mini alpine
这里Alpine Linux版本选择3.5，下载相应的apk tool，把基本的系统写入到空镜像中

REL="v3.5"
REL=${REL:-edge}
MIRROR=${MIRROR:-http://nl.alpinelinux.org/alpine}
REPO=$MIRROR/$REL/main
ARCH=$(uname -m)
ROOTFS=${ROOTFS:-alpine}
APKV=`curl -s $REPO/$ARCH/APKINDEX.tar.gz | tar -Oxz | grep -a '^P:apk-tools-static$' -A1 | tail -n1 | cut -d: -f2`
mkdir tmp
curl -s $REPO/$ARCH/apk-tools-static-${APKV}.apk | tar -xz -C tmp sbin/apk.static
tmp/sbin/apk.static --repository $REPO --update-cache --allow-untrusted --root $ROOTFS --initdb add alpine-base
printf '%s\n' $REPO > $ROOTFS/etc/apk/repositories
接下来最重要的是写分区表，将下面的东西写入到alpine/etc/fstab文件中

#
# /etc/fstab: static file system information
#
# <file system>   <dir> <type>    <options> <dump>    <pass>
LABEL=ROOT / auto defaults 1 1
其他的配置，都可以进入镜像后再操作。

由于宿主机里面本身就有go版本的ss了，直接从系统里面复制一下，配置里面修改个端口就行了。

mkdir alpine/etc/shadowsocks-go
cp /usr/local/bin/ss-goserver alpine/usr/local/bin
cp /etc/shadowsocks-go/config.json alpine/etc/shadowsocks-go
如果没有，可以直接去官网下载最新版。

顺便修改下alpine/etc/sysctl.conf，配合ss优化一番。

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
镜像设定完毕后，卸载掉镜像。
umount ./alpine

##2，制作UML的可执行文件vmlinux

安装依赖
apt-get install build-essential libncurses5-dev bc screen
在https://www.kernel.org/上找到需要的内核。

这里以4.10.1内核为例。

wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.10.1.tar.xz
tar xf linux-4.10.1.tar.xz
rm linux-4.10.1.tar.xz
cd linux-4.10.1
make defconfig ARCH=um
make menuconfig ARCH=um
在配置菜单中，除了把TCP_BBR选上，还要保证内核支持net.ipv4.tcp_syncookies和net.core.default_qdisc选项。

通过按空格来选择项目，只有*状态才是构建，下面是基本的内容。

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

配置完成后开始构建以及可执行文件减肥

make ARCH=um vmlinux
strip -s vmlinux

##3，在UML中配置Apline Linux

为了让Apline Linux有网可用，外部网络可穿透9000-19000端口到内部，要在宿主机上开启tap，设置iptables
D_I=`ip route show 0/0 | sort -k 7 | head -n 1 | sed -n 's/^default.* dev \([^ ]*\).*/\1/p'`
sudo ip tuntap add tap0 mode tap 
sudo ip addr add 10.0.0.1/24 dev tap0 
sudo ip link set tap0 up 
sudo iptables -P FORWARD ACCEPT
sudo iptables -t nat -A POSTROUTING -o ${D_I} -j MASQUERADE
sudo iptables -t nat -A PREROUTING -i ${D_I} -p tcp --dport 9000:19000 -j DNAT --to-destination 10.0.0.2
然后，开启镜像
sudo ./vmlinux ubda=alpine_mini rw eth0=tuntap,tap0 mem=64m
通过screen命令来操作小虚拟机，下面的X，根据具体情况修改。
screen /dev/pts/X
系统默认下，root用户没有密码。系统中，可以执行setup-alpine命令来一步一步配置系统。

需要注意的是网络设定，Ip address for eth0=10.0.0.2，gateway=10.0.0.1，netmask=255.255.255.0，DNS nameserver=8.8.8.8。

其他的根据自己需要来设定。

开机自启的网络有bug，需要重新启动网络才可用。

这里选择设定开机自启动脚本来简单修复下。

rc-update add local default
索性加入swapfile和ss的开机自启动，先创建swapfile

dd if=/dev/zero of=/swapfile bs=1M count=64
chmod 600 /swapfile
然后用vi编辑/etc/local.d/my.start文件
#!/bin/sh
# swap on
/sbin/mkswap /swapfile
/sbin/swapon /swapfile
# fix net
sleep 3
/etc/init.d/networking restart
# ss
/usr/bin/nohup /usr/local/bin/ss-goserver -c /etc/shadowsocks-go/config.json > /dev/null 2>&1 &
不要忘了加上可写的权限
chmod +x /etc/local.d/my.start
最后，reboot一下看看配置是否都生效了。

如果需要安装其他的软件的话，例如curl，可以使用它提供的包管理软件apk

apk add curl
##4，总结

实际上镜像和vmlinux只需要做一遍，在其他的64位linux系统上，配置好tap和转发，再次复用它们即可。