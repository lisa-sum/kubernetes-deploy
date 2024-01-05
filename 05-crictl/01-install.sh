#!/bin/sh

# 删除之前的
rm -rf /etc/crictl.yaml

export CRICTL_VERSION="v1.29.0"
export ARCH="amd64"
export DOWNLOAD_DIR="/usr/local/bin"
sudo mkdir -p "$DOWNLOAD_DIR"

curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" | sudo tar -C $DOWNLOAD_DIR -xz

# 修改`crictl`配置文件，使用`containerd`作为Kubernetes默认的容器运行时, 即crictl调用containerd管理Pod
cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 使用crictl测试一下，确保可以打印出版本信息并且没有错误信息输出
crictl --runtime-endpoint=unix:///run/containerd/containerd.sock  version

cat /etc/crictl.yaml
# 输出版本
crictl -v
