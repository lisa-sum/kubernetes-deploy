# 取消kubelet的挂载
sudo umount /var/lib/kubelet/pods/*

# 停止正在运行的容器和删除这些容器的镜像
crictl images | awk '{print $3}' | xargs -n 1 crictl rmi

# 用crictl命令停止和删除不存在的容器
if [ -n "$running_containers" ]; then
    # Stop and remove running containers
    echo "Stopping and removing running containers..."
    echo "$running_containers" | xargs -n 1 crictl stop
    echo "$running_containers" | xargs -n 1 crictl rm
else
    echo "No running containers found."
fi

# 删除未使用(非正在运行的)的镜像
crictl rmi --prune

systemctl stop kubeadm
systemctl stop kubelet
systemctl stop kubectl

# service
rm -rf /etc/systemd/system/kube*

# sock
rm -rf /var/run/containerd/*
rm -rf /var/run/kubeadm/*
rm -rf /var/run/kubelet/*
rm -rf /var/run/containerd/*
rm -rf /run/containerd/*
rm -rf /run/containerd/*
rm -rf /run/kubeadm/*
rm -rf /run/kubelet/*

systemctl disenable kubeadm
systemctl disenable kubelet
systemctl disenable kubectl

# 删除Kubernetes的配置与安装的包
sudo apt purge -y kubeadm kubectl kubelet kubernetes-cni kube*
sudo apt-mark unhold kubeadm
sudo apt-mark unhold kubelet
sudo apt-mark unhold kubectl
sudo apt remove -y kubeadm kubelet kubectl
sudo apt remove -y containerd

# 自动删除不需要的依赖项：
#sudo apt autoremove -y

# 清理Docker容器和镜像（如果使用Docker）：
#docker image prune -a -f
#systemctl restart docker
#sudo apt purge -y docker-engine docker docker.io docker-ce docker-ce-cli containerd containerd.io runc --allow-change-held-packages

# 重置节点
kubeadm reset -f

# 清理IPVS规则
sudo ipvsadm -C

# 删除网卡
#apt install net-tools # Ubuntu
#yum install net-tools # RedHat

# flannel
ifconfig flannel.1 down
ip link delete flannel.1

# CNI
ifconfig cni0 down
ip link delete cni0

# kube-ipvs0
ifconfig kube-ipvs0 down
ip link delete kube-ipvs0

ifconfig cilium_netdown
ip link delete kube-cilium_netdown

ifconfig cilium_host down
ip link delete cilium_host

ifconfig cilium_vxlan down
ip link delete cilium_vxlan

# 清理iptables规则：
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

sudo rm -rf /etc/kubernetes/ # Kubernetes的安装位置

# 删除Kubernetes的相关依赖
sudo rm -rf \
/var/lib/cni \
/var/lib/containerd  \
/var/lib/docker  \
/var/lib/etcd   \
/var/lib/dockershim \
/var/lib/kubelet \
/etc/cni \
/opt/cni \
/opt/cni/bin \
/etc/kubernetes  \
/var/run/kubernetes \
~/.kube/* \
/run/containerd \
/usr/local/bin/kube* \
/usr/local/bin/container* \
/usr/local/bin/ctr \
/usr/local/bin/crictl

crictl -v
ctr -v
socat -h
runc -h
conntrack -h
ipvsadm -h