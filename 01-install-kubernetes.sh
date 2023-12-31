#!/bin/sh

set -x

# 清除旧安装
systemctl stop kubeadm
systemctl stop kubelet
systemctl stop kubectl
sudo apt purge -y kubeadm kubectl kubelet kubernetes-cni kube*
sudo apt-mark unhold kubeadm
sudo apt-mark unhold kubelet
sudo apt-mark unhold kubectl
sudo apt remove -y kubeadm kubelet kubectl
sudo apt remove -y containerd
rm -rf /usr/local/bin/kube*
rm -rf /usr/bin/kube*
rm -rf /etc/systemd/system/kube*
rm -rf /var/lib/kube*

# 安装 kubeadm、kubelet
# https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
export DOWNLOAD_HOME="/home/kubernetes"
mkdir -p $DOWNLOAD_HOME
cd "$DOWNLOAD_HOME" || exit

RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
ARCH="amd64"

sudo curl -LO "https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubeadm.sha256}"
output=$(echo "$(cat kubeadm.sha256) kubeadm" | sha256sum -c)
status=$?
if [ $status -ne 0 ]; then
  echo "kubeadm 的SHA256 校验失败，退出并报错"
  exit 1
fi
  echo "kubeadm 的SHA256 校验成功"

sudo chmod +x kubeadm

sudo curl -LO "https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubelet,kubelet.sha256}"
output=$(echo "$(cat kubelet.sha256) kubelet" | sha256sum -c)
status=$?
if [ $status -ne 0 ]; then
  echo "kubelet 的SHA256 校验失败，退出并报错"
  exit 1
fi
echo "kubelet 的SHA256 校验成功"
sudo chmod +x kubelet

sudo curl -LO "https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubectl,kubectl.sha256}"
output=$(echo "$(cat kubectl.sha256) kubectl" | sha256sum -c)
status=$?
if [ $status -ne 0 ]; then
  echo "kubectl 的SHA256 校验失败，退出并报错"
  exit 1
fi
echo "kubectl 的SHA256 校验成功"
sudo chmod +x kubectl
DOWNLOAD_DIR="/usr/local/bin"
sudo install -o root -g root -m 0755 kubectl $DOWNLOAD_DIR/kubectl

# 并添加 kubelet 系统服务
# 查看 https://github.com/kubernetes/release/tree/master 获取RELEASE_VERSION的版本号
DOWNLOAD_DIR="/usr/local/bin"
RELEASE_VERSION="v0.16.4"

if ! wget -q "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service"; then
echo "下载失败, 正在使用内置的文件进行替换, 但可能不是最新的, 可以进行手动替换"
cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$DOWNLOAD_DIR
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
else
  sed -i "s:/usr/bin:${DOWNLOAD_DIR}:g" kubelet.service
  cp kubelet.service /etc/systemd/system/kubelet.service
fi

# kubeadm 包自带了关于 systemd 如何运行 kubelet 的配置文件。 请注意 kubeadm 客户端命令行工具永远不会修改这份 systemd 配置文件。 这份 systemd 配置文件属于 kubeadm DEB/RPM 包
# https://kubernetes.io/zh-cn/docs/reference/setup-tools/kubeadm/kubeadm-init/#kubelet-drop-in

# 获取配置文件内容并修改该文件的内容, 把kubelet二进制文件的路径替换为用户定义的路径
# 并输出到 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf 文件中
sudo mkdir -p /etc/systemd/system/kubelet.service.d
if ! wget -q "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf"; then
echo "下载失败, 正在使用内置的文件进行替换, 但可能不是最新的, 可以进行手动替换"
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << EOF
# 注意：此 dropin 仅适用于 kubeadm 和 kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# 这是一个在运行时由 "kubeadm init" 和 "kubeadm join" 生成的文件，动态填充 KUBELET_KUBEADM_ARGS 变量
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# 这是用户可以用来覆盖 kubelet 参数的文件，作为最后的手段。最好用户应该使用配置文件中的 .NodeRegistration.KubeletExtraArgs 对象。KUBELET_EXTRA_ARGS 应该从这个文件中获取。
EnvironmentFile=-/etc/sysconfig/kubelet
ExecStart=
ExecStart=${DOWNLOAD_DIR}/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARG
EOF
else
  sed -i "s:/usr/bin:${DOWNLOAD_DIR}:g" 10-kubeadm.conf
  sudo cp 10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
fi

## 连接失败的情况: 把下面代码取消注释:
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
#ExecStart=${DOWNLOAD_DIR}/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARG
#EOF

#!/bin/sh

# 执行第一个任务

# 查看是否生效

cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sleep 3

systemctl daemon-reload

systemctl enable --now kubelet
systemctl enable kubelet
systemctl status kubelet

systemctl enable kubeadm
systemctl status kubeadm

systemctl restart containerd

kubeadm version
sleep 3

kubelet --version
sleep 3

kubectl version --client
sleep 3
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
kind: InitConfiguration
bootstrapTokens:
  - groups:
      # 指定用于节点引导的安全组
      - system:bootstrappers:kubeadm:default-node-token
    token: "9a08jv.c0izixklcxtmnze7"
    ttl: 24h0m0s # 令牌的有效期限
    usages:
      - signing # 用于签名请求
      - authentication # 用于身份验证
localAPIEndpoint:
  # masterIP 主节点用于广播的地址
  advertiseAddress: 192.168.2.152
  # Kubernetes API 服务器监听的端口
  bindPort: 6443
nodeRegistration:
  name: "master-node-152" # 该控制节点的名称, 也就是出现在kubectl get no的名称
  # CRI（容器运行时接口）的通信 socket 用来读取容器运行时的信息。 此信息会被以注解的方式添加到 Node API 对象至上，用于后续用途。
  criSocket: unix:///var/run/containerd/containerd.sock
  # 镜像拉取策略。 这两个字段的值必须是 "Always"、"Never" 或 "IfNotPresent" 之一。 默认值是 "IfNotPresent"，也是添加此字段之前的默认行为
  imagePullPolicy: IfNotPresent
  # 定 Node API 对象被注册时要附带的污点。 若未设置此字段（即字段值为 null），默认为控制平面节点添加控制平面污点。 如果你不想污染你的控制平面节点，可以将此字段设置为空列表
  taints: null
  # 提供一组在当前节点被注册时可以忽略掉的预检错误。 例如：IsPrevilegedUser,Swap。 取值 all 忽略所有检查的错误。
  #ignorePreflightErrors:
  #  - IsPrivilegedUser
skipPhases: # 是命令执行过程中要略过的阶段（Phases）。 通过执行命令 kubeadm init --help 可以获得阶段的列表。 参数标志 "--skip-phases" 优先于此字段的设置
  - addon/kube-proxy # 忽略kube-proxy, 许多CNI网络插件都可以代替kube-proxy的功能, 此时可以省略, 除非你真的很懂, 否则不要跳过
---
apiServer:
  # certSANs 设置 API 服务器签署证书所用的额外主题替代名（Subject Alternative Name，SAN）。
  certSANs:
    # 集群中各个节点的 IP 地址、域名、负载均衡、或者集群的公共访问地址作为 certSANs 字段的值
    - 192.168.2.152
    - "master-node-152"
    - 192.168.2.155
    - "worker-node-155"
    - 192.168.2.160
    - "worker-node-160"
    - 192.168.2.100
    - "worker-node-100"
    - 192.168.2.101
    - "worker-node-101"
    - 192.168.2.102
    - "worker-node-102"
    - "kubernetes"
    - "kubernetes.default"
    - "kubernetes.default.svc"
    - "kubernetes.default.svc.cluster.local"
  extraArgs:
    # API 服务器的授权模式
    authorization-mode: Node,RBAC
#  extraVolumes:
#    - name: "some-volume"
#      hostPath: "/etc/some-path"
#      mountPath: "/etc/some-pod-path"
#      readOnly: false
#      pathType: File
  # 控制平面的超时时间
  timeoutForControlPlane: 1m0s
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
# 版本信息
kubernetesVersion: 1.29.0
# 证书目录路径
certificatesDir: /etc/kubernetes/pki
# 集群名称。
clusterName: kubernetes
# 控制器管理器配置
controllerManager: {}
# DNS 配置
dns: {}
# etcd 数据库的配置。例如使用这个部分可以定制本地 etcd 或者配置 API 服务器 使用一个外部的 etcd 集群。
etcd:
  local:
    # etcd 数据存储目录
    dataDir: /var/lib/etcd
#    imageRepository: "registry.k8s.io"
#    imageTag: "3.2.24"
#    extraArgs:
#      listen-client-urls: "http://10.100.0.1:2379"
#    serverCertSANs:
#      - "ec2-10-100-0-1.compute-1.amazonaws.com"
#    peerCertSANs:
#      - "10.100.0.1"
# external:
#   endpoints:
#   - "10.100.0.1:2379"
#   - "10.100.0.2:2379"
#   caFile: "/etcd/kubernetes/pki/etcd/etcd-ca.crt"
#   certFile: "/etcd/kubernetes/pki/etcd/etcd.crt"
#   keyFile: "/etcd/kubernetes/pki/etcd/etcd.key"
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers # 镜像源
# 为控制面设置一个稳定的 IP 地址或 DNS 名称。
# 取值可以是一个合法的 IP 地址或者 RFC-1123 形式的 DNS 子域名，二者均可以带一个 可选的 TCP 端口号。
# 如果 controlPlaneEndpoint 未设置，则使用 advertiseAddress + bindPort。 如果设置了 controlPlaneEndpoint，但未指定 TCP 端口号，则使用 bindPort。
# 可能的用法有：
# 在一个包含不止一个控制面实例的集群中，该字段应该设置为放置在控制面 实例之前的外部负载均衡器的地址。
# 在带有强制性节点回收的环境中，controlPlaneEndpoint 可以用来 为控制面设置一个稳定的 DNS。
# 负载均衡地址或者master的主机
controlPlaneEndpoint: "192.168.2.152:6443"
# 其中包含集群的网络拓扑配置。使用这一部分可以定制 Pod 的 子网或者 Service 的子网。
networking:
  # Kubernetes 服务所使用的的 DNS 域名。 默认值为 "cluster.local"。
  dnsDomain: cluster.local
  # 为 Pod 所使用的子网
  podSubnet: 10.244.0.0/16
  # Kubernetes 服务所使用的的子网。 默认值为 "10.96.0.0/12"。
  serviceSubnet: 10.96.0.0/12
# 调度器配置
scheduler: {}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: "192.168.2.152"
port: 20250
serializeImagePulls: false
# kubelet 将在以下情况之一驱逐 Pod:
evictionHard:
  # 可用内存低于设定的值时
  memory.available:  "100Mi"
  nodefs.available:  "10%"
  # 当节点主文件系统的已使用 inode超过设定的值时
  nodefs.inodesFree: "5%"
  # 当镜像文件系统的可用空间小于
  imagefs.available: "15%"
# 是 kubelet 用来操控宿主系统上控制组（CGroup） 的驱动程序（cgroupfs 或 systemd）
# 当 systemd 是初始化系统时， 不 推荐使用 cgroupfs 驱动，因为 systemd 期望系统上只有一个 cgroup 管理器。
# 此外，如果你使用 cgroup v2， 则使用systemd值
cgroupDriver: "systemd"
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

# 或者自动化: https://kubernetes.io/zh-cn/docs/reference/setup-tools/kubeadm/kubeadm-init/#automating-kubeadm
kubeadm token generate
kubeadm certs certificate-key

cat > kubeadm-join.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: "9a08jv.c0izixklcxtmnze7"
    apiServerEndpoint: "192.168.2.152:6443"
    caCertHashes:
      - "sha256:e462571f0388602594f1abdbee04f8834e5d967008cde03d67865fbe0bd6dfde"
nodeRegistration:
  name: "worker-node-155"
  criSocket: "/var/run/containerd/containerd.sock"
EOF

set +x
