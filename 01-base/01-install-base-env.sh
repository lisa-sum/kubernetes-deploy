#!/bin/sh

set -x

# 验证每个节点的 MAC 地址和product_uuid是否唯一](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#verify-mac-address
sudo cat /sys/class/dmi/id/product_uuid

sleep 4

# 设置为静态路由
# Ubuntu示例:
cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.back
cat > /etc/netplan/00-installer-config.yaml <<EOF
# 参考: https://ubuntuforums.org/showthread.php?t=2491245&p=14159782
network:
  version: 2
  renderer: networkd
  ethernets:
    ens160: # 网卡名称
      dhcp4: false # 是否启用IPV4的DHCP
      dhcp6: false # 是否启用IPV6的DHCP
      addresses: # 网卡的IP地址和子网掩码。例如，192.168.2.152/24 表示IP地址为192.168.2.152，子网掩码为255.255.255.0
        - 192.168.2.152/24
      nameservers: # 用于指定DNS服务器地址的部分
          addresses: # 列出DNS服务器的IP地址
            - 192.168.0.6
      routes: # 配置静态路由
          - to: default # 目标网络地址，default 表示默认路由
            via: 192.168.2.1 # 指定了路由数据包的下一跳地址，192.168.2.1 表示数据包将通过该地址进行路由
            metric: 100 # 指定了路由的优先级，数值越小优先级越高
            on-link: true # 表示数据包将直接发送到指定的下一跳地址，而不需要经过网关
      mtu: 1500 # 最大传输单元（MTU），表示网络数据包的最大尺寸
EOF

# Netplan配置文件不应该对其他用户开放访问权限 过于开放的权限，这可能会导致安全风险
sudo chmod 600 /etc/netplan/00-installer-config.yaml

# 生成和应用更改
sudo netplan generate
sudo netplan apply

# 控制节点需要开启以下下端口:
# 协议	方向	端口范围	目的	使用者
# TCP	入站	6443	Kubernetes API server	所有
# TCP	入站	2379-2380	etcd server client API	kube-apiserver, etcd
# TCP	入站	10250	Kubelet API	自身, 控制面
# TCP	入站	10259	kube-scheduler	自身
# TCP	入站	10257	kube-controller-manager	自身
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 10259/tcp
sudo ufw allow 10257/tcp

# 工作节点需要开启以下下端口:
# 协议	方向	端口范围	目的	使用者
# TCP	入站	10250	Kubelet API	自身, 控制面
# TCP	入站	30000-32767	NodePort Services†	所有

sudo ufw allow 10250/tcp
sudo ufw allow 30000:32767/tcp

# 设置控制节点与工作节点
export master_node_152="192.168.2.152"
export worker_node_155="192.168.2.155"
export worker_node_160="192.168.2.160"
export worker_node_100="192.168.2.100"
export worker_node_101="192.168.2.101"
export worker_node_102="192.168.2.102"

#  时间同步
apt install ntpdate -y # Ubuntu
ntpdate time.windows.com

# runc 是操作系统级别的软件包, 用于与Containerd Docker Podman等CRI底层的OCI工具
# Containerd -> runc
# 少数情况下, 系统可能没有安装runc或者配置不正确
apt install -y runc

# 修改Hosts
cat > /etc/hosts << EOF
# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$master_node_152 master-node-152
$worker_node_155 worker-node-155
$worker_node_160 worker-node-160
$worker_node_100 worker-node-100
$worker_node_101 worker-node-101
$worker_node_102 worker-node-102
EOF

# systemd-resolved
systemctl restart systemd-resolved
#systemctl status systemd-resolved

# 关闭SELinux
sudo setenforce 0 # 临时禁用, 重启变回
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config # 禁用

# SWAP分区
#sudo swapoff -a
#sed -i '/^\/.*swap/s/^/#/' /etc/fstab
#sudo mount -a
cat /etc/fstab
sudo blkid | grep swap
sleep 1

# 转发IPv4并让iptables看到桥接的流量
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
sleep 1

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# 通过运行以下命令验证是否加载了`br_netfilter`，`overlay`模块：
lsmod | grep br_netfilter
lsmod | grep overlay
sleep 1

# IPVS
apt install ipset ipvsadm -y

cat > /etc/modules-load.d/ipvs.conf << EOF
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

systemctl restart systemd-modules-load.service

lsmod | grep -e ip_vs -e nf_conntrack
sleep 1

cut -f1 -d " "  /proc/modules | grep -e ip_vs -e nf_conntrack
sleep 1

echo "/etc/sysctl.d/k8s.conf:"
cat /etc/sysctl.d/k8s.conf
sleep 1

echo "/etc/modules-load.d/k8s.conf:"
cat /etc/modules-load.d/k8s.conf
sleep 1

echo "blkid | grep swap:"
sudo blkid | grep swap

lsmod | grep br_netfilter
lsmod | grep overlay

set +x
