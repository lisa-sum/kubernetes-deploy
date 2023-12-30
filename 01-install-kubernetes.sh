#!/bin/sh

set -x

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
DOWNLOAD_DIR="/usr/local/bin"
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

kubeadm version
kubelet --version

systemctl enable --now kubelet

# kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#enable-kubectl-autocompletion
ARCH="amd64"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

#sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo chmod 0755 /usr/local/bin/kubectl
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

kubectl version --client
# 查看版本的详细视图
# kubectl version --client --output=yaml

kubeadm config images list

# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.29.0
# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.29.0
# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.29.0
# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.29.0
# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/coredns/coredns:v1.11.1
# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9
# ctr images pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.5.10-0

# crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.29.0
# crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.29.0
# crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.29.0
# crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.29.0
# crictl pull registry.k8s.io/coredns/coredns:v1.11.1
# crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9
# crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.5.10-0

ls /var/run/containerd/
ls /run/containerd/

# 初始化集群
cat > kubeadm-init-conf.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
  - groups:
      - system:bootstrappers:kubeadm:default-node-token # 指定用于节点引导的安全组
    token: abcdef.0123456789abcdef # 引导令牌，用于节点加入集群时的验证
    ttl: 24h0m0s # 令牌的有效期限
    usages:
      - signing # 用于签名请求
      - authentication # 用于身份验证
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.2.152 # masterIP 主节点用于广播的地址
  bindPort: 6443 # Kubernetes API 服务器监听的端口
nodeRegistration:
  kubeletExtraArgs:
    node-ip: 192.168.2.152 # 指定本机的ip地址,用于kubelet向master注册,同advertiseAddress kubelet 使用的节点 IP 地址
  criSocket: unix:///var/run/containerd/containerd.sock # CRI（容器运行时接口）的通信 socket
  imagePullPolicy: IfNotPresent  # 镜像拉取策略
  taints: null
---
apiServer:
  certSANs:
    # 这里需要包含负载均衡、所有master节点的hostname和ip
    - "master-node-152"
    - "worker-node-155"
    - "worker-node-160"
    - "worker-node-100"
    - "worker-node-101"
    - "worker-node-102"
  extraArgs:
    authorization-mode: Node,RBAC # API 服务器的授权模式
  timeoutForControlPlane: 4m0s # 控制平面的超时时间
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: 1.29.0 # 版本信息
certificatesDir: /etc/kubernetes/pki # 证书目录路径
clusterName: kubernetes
controllerManager: {} # 控制器管理器配置
dns: {} # DNS 配置
etcd:
  local:
    dataDir: /var/lib/etcd # etcd 数据存储目录
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers # 镜像源
controlPlaneEndpoint: master-node-152:6443 # 负载均衡地址或者master的主机

networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16 # Pod 网络子网
  serviceSubnet: 10.96.0.0/12 # 服务网络子网
scheduler: {} # 调度器配置
---
apiVersion: kubelet.config.k8s.io/v1beta1
healthzBindAddress: 127.0.0.1 # 健康检查绑定地址, 推荐默认值. 荐将此地址设置为 127.0.0.1（即本地回环地址），因为这样可以限制健康检查接口只在本地机器上可用，增加安全性。如果设置为一个外部地址，则此接口在网络上可见，可能会暴露给不必要的安全风险
healthzPort: 10248 # 健康检查绑定端口
kind: KubeletConfiguration
cgroupDriver: systemd # 控制组驱动, 可选为systemd, cgroupfs, 推荐systemd
failSwapOn: true # 当存在 swap 时是否失败
maxPods: 200 # 最大 Pod 数量, 默认值为110
rotateCertificates: false #启用客户端证书轮换。Kubelet 将从 certificates.k8s.io API 请求新证书。这需要审批者批准证书签名请求。默认值：false
staticPodPath: /etc/kubernetes/manifests
evictionHard: # 信号名称与定义硬逐出阈值的数量的映射。例如： {"memory.available": "300Mi"} .若要显式禁用，请在任意资源上传递 0% 或 100% 阈值。默认值：memory.available： “100Mi” nodefs.available： “10%” nodefs.inodesFree： “5%” imagefs.available： “15%”
  imagefs.available: "10%"
  memory.available: "2Gi"
  nodefs.available: "5%"
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
EOF

# 安装
kubeadm init \
--config=kubeadm-init-conf.yaml \
--skip-phases addon/kube-proxy \
--v=5

set +x
