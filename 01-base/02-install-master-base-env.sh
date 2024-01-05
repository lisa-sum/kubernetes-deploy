#!/bin/sh

set -x

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

# 获取当前版本的Kubernetes组件的镜像列表
# 并且替换为国内的阿里云镜像进行下载
VERSION="v1.29.0"
# registry.cn-hangzhou.aliyuncs.com/google_containers
kubeadm config images list --kubernetes-version $VERSION \
| sed 's|registry.k8s.io|crictl pull registry.aliyuncs.com/google_containers|g' \
> download_images.sh

sudo sh download_images.sh

# coredns/coredns:v1.11.1和pause:3.9一般都下载失败, 因为阿里云镜像没有. 需要手动从registry.k8s.io下载
# 也可以跳过该步骤, 因为init也会自动下载, 而且init阶段却很奇怪的就可以下载成功, 有兴趣可以研究
crictl pull registry.k8s.io/coredns/coredns:v1.11.1
crictl pull registry.k8s.io/pause:3.9

ls /var/run/containerd/
ls /run/containerd/

# 查看默认的kubelet的配置
kubeadm config print init-defaults --component-configs KubeletConfiguration

# 预检
netstat -tuln | grep 6443
netstat -tuln | grep 10259
netstat -tuln | grep 10257

lsof -i:6443 -t
lsof -i:10259 -t
lsof -i:10257 -t

if kubeadm init phase preflight --dry-run --config kubeadm-init-conf.yaml; then
  echo "预检成功"
  # 安装
  kubeadm init \
  --config=kubeadm-init-conf.yaml \
  --v=7
else
  echo "命令执行失败"
  kubeadm reset -f
fi

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

cat >> ~/.bashrc <<EOF
alias kt='kubectl '
alias kgp='kubectl get po '
alias ktl='kubectl logs '
alias kta='kubectl apply -f '
alias ktd='kubectl describe '
alias ktdp='kubectl delete -f '
alias ktna='kubectl get no -owide'
alias ktpa='kubectl get po -owide -n '
alias kts='kubectl get svc -owide -n '
EOF

source ~/.bashrc

set +x
