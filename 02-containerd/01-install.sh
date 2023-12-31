#!/bin/sh
set -x

# 删除之前的
rm -rf /opt/containerd/
rm -rf /home/containerd
rm -rf /etc/containerd/
rm -rf /etc/systemd/system/containerd.service
rm -rf /etc/modules-load.d/containerd.conf
rm -rf /etc/sysctl.d/99-kubernetes-cri.conf

# 安装containerd
export VERSION="1.7.11"
#export ARCH="arm64"
export ARCH="amd64"
mkdir -p /home/containerd
cd /home/containerd
if [ -f "containerd-$VERSION-linux-$ARCH.tar.gz" ]; then
    echo "文件存在"
    tar -zxvf containerd-$VERSION-linux-$ARCH.tar.gz -C /usr/local/
else
    echo "文件不存在"
    wget https://github.com/containerd/containerd/releases/download/v${VERSION}/containerd-${VERSION}-linux-${ARCH}.tar.gz
    tar -zxvf containerd-$VERSION-linux-$ARCH.tar.gz -C /usr/local/
fi

echo "正在生成containerd的文件"
# 生成containerd的配置文件
mkdir -p /etc/containerd/
containerd config default | tee /etc/containerd/config.toml
# 配置文件默认在`/etc/containerd/config.toml` 这里仅修改两处配置, 读者可以修改自己想要的配置
# 替换为国内镜像, 国内服务器请使用
sed -i 's#registry.k8s.io/pause:3.8#registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9#g' /etc/containerd/config.toml
# 当 systemd 是选定的初始化系统时, 应当选择SystemdCgroup = true, 否则不需要修改
# 参考: https://kubernetes.io/zh-cn/docs/setup/production-environment/container-runtimes/#containerd-systemd
sed -i 's#SystemdCgroup = false#SystemdCgroup = true#g' /etc/containerd/config.toml

# 下载containerd.service
# 配置containerd的service单元文件
# 命令说明:
# 1. 如果存在containerd.service,内容 可能不是最新的, 而且也会影响wget下载下来的文件名
# 删除当前目录的containerd.service, 如果文件不存在, rm -rf 也不会删除, 无需判断文件是否存在
# 2. 从Github的containerd下载containerd.service文件, 如果下载失败, 则使用内置的文件进行替换
rm -rf ./containerd.service
if ! wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service; then
  echo "下载containerd.service失败, 正在使用内置的文件进行替换, 但可能不是最新的, 可以进行手动替换"
  cat > /etc/systemd/system/containerd.service << EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
else
  sudo cat containerd.service | sudo tee /etc/systemd/system/containerd.service
fi

# 所有节点均需安装与配置, 根据实际需求, 推荐Kubernetes安装v1.24版本以上使用containerd. 本教程只使用containerd
# 创建/etc/modules-load.d/containerd.conf配置文件，确保在系统启动时自动加载所需的内核模块，以满足容器运行时的要求
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 应用 sysctl 参数而无需重新启动
sudo sysctl --system

systemctl daemon-reload
systemctl enable containerd --now
#systemctl status containerd

# 校验配置文件
grep -nE "sandbox_image|SystemdCgroup" /etc/containerd/config.toml

cat /etc/modules-load.d/containerd.conf

ctr -v

set +x
