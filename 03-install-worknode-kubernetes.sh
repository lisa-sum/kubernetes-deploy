#!/bin/sh

set -x

export master_node_152="192.168.2.152"
export worker_node_155="192.168.2.155"
export worker_node_160="192.168.2.160"
export worker_node_100="192.168.2.100"
export worker_node_101="192.168.2.101"
export worker_node_102="192.168.2.102"

# 安装 kubeadm、kubelet
# https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
ARCH="amd64"

export DOWNLOAD_DIR="/usr/local/bin"
cd "$DOWNLOAD_DIR"

sudo curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}

sudo chmod +x {kubeadm,kubelet}

# 并添加 kubelet 系统服务
# 查看 https://github.com/kubernetes/release/tree/master 获取RELEASE_VERSION的版本号
RELEASE_VERSION="v0.16.4"
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service
sudo mkdir -p /etc/systemd/system/kubelet.service.d
#rm -rf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# 连接失败的情况: 把下面代码取消注释:
#cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << EOF
## Note: This dropin only works with kubeadm and kubelet v1.11+
#[Service]
#Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
#Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
## This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
#EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
## This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
## the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
#EnvironmentFile=-/etc/sysconfig/kubelet
#ExecStart=
#ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARG
#EOF

# 查看是否生效
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# kubelet service
rm -rf /etc/systemd/system/kubelet.service
cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# kubeadm service
rm -rf /etc/systemd/system/kubeadm.service
cat > /etc/systemd/system/kubeadm.service << EOF
[Unit]
Description=Kubernetes kubeadm
Documentation=https://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/kubeadm
Restart=on-failure
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl start kubelet
systemctl enable kubelet
systemctl status kubelet

systemctl start kubeadm
systemctl enable kubeadm
systemctl status kubeadm

systemctl restart containerd

kubeadm version
kubelet --version

systemctl enable --now kubelet

# kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#enable-kubectl-autocompletion
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

kubectl version --client
# 查看版本的详细视图
# kubectl version --client --output=yaml

ls /var/run/containerd/
ls /run/containerd/

systemctl restart containerd

set +x
