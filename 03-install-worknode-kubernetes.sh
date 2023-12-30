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

ls /var/run/containerd/
ls /run/containerd/

systemctl restart containerd

set +x
