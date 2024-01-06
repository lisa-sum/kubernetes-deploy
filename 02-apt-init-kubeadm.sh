#!/bin/sh

set -x

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
crictl pull registry.k8s.io/pause:3.9&
crictl pull registry.k8s.io/coredns/coredns:v1.11.1&

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

mkdir -p /etc/kubernetes/manifests
if kubeadm init phase preflight --dry-run --config kubeadm-init-conf.yaml; then
  echo "预检成功"
  # 安装
  kubeadm init \
  --config=kubeadm-init-conf.yaml \
  --upload-certs \
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
