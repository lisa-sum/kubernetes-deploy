#!/bin/sh

set -x

uname -m
uname -r

# 开启eBPF


# 判断架构
if [ "$(uname -m)" = "x86_64" ]; then
    echo "This is an AMD64 architecture."
elif [ "$(uname -m)" = "aarch64" ]; then
    echo "This is an AArch64 architecture."
else
    echo "This architecture is not recognized as AMD64 or AArch64."
    exit
fi

# 判断内核版本
if [ "$(uname -r | cut -d. -f1)" -gt 4 ] || { [ "$(uname -r | cut -d. -f1)" -eq 4 ] && [ "$(uname -r | cut -d. -f2)" -gt 19 ]; } || { [ "$(uname -r | cut -d. -f1)" -eq 4 ] && [ "$(uname -r | cut -d. -f2)" -eq 19 ] && [ "$(uname -r | cut -d. -f3)" -gt 57 ]; }; then
    echo "内核版本大于4.19.57"
else
    echo "内核版本不大于4.19.57"
    exit
fi

# 错误显示conntrack未在系统路径中找到。conntrack是Linux内核中用于连接跟踪的工具，通常用于网络连接的状态跟踪
sudo apt update -y
sudo apt install conntrack -y

# 默认情况下，Cilium 会自动挂载 cgroup v2 文件系统，以在路径 /run/cilium/cgroupv2 中附加 BPF cgroup 程序。
# 为此，它需要将主机 /proc 挂载到 DaemonSet 临时启动的 init 容器中。
# 如果需要禁用自动挂载，请使用 指定 --set cgroup.autoMount.enabled=false ，并设置 --set cgroup.hostRoot 已挂载 cgroup v2 文件系统的主机挂载点。
# 例如，如果尚未挂载，则可以通过在主机上运行以下命令来挂载 cgroup v2 文件系统，并指定 --set cgroup.hostRoot=/sys/fs/cgroup

# 这会将 Cilium 安装为 CNI 插件，并替换 eBPF kube-proxy，以实现对 ClusterIP、NodePort、LoadBalancer 类型的 Kubernetes 服务和具有 externalIP 的服务的处理。
# 此外，eBPF kube-proxy 的替换也支持容器的 hostPort，因此不再需要使用 portmap
# mount -t cgroup2 none /sys/fs/cgroup

# 完全使用cilium代替kube-proxy, 如果集群现有kube-proxy,那么将卸载, 并且cilium安装完成之前集群服务都不可用
kubectl -n kube-system delete ds kube-proxy
# Delete the configmap as well to avoid kube-proxy being reinstalled during a Kubeadm upgrade (works only for K8s 1.19 and newer)
kubectl -n kube-system delete cm kube-proxy
# Run on each node with root permissions:
iptables-save | grep -v KUBE | iptables-restore

# cilium cli
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CILIUM_CLI_VERSION="v0.15.19"
CLI_ARCH="amd64"
## if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
## curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
## sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
wget https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum

sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin

rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# 使用帮助
# Cilium CLI - 用于在 Kubernetes 中安装、管理和排查 Cilium 集群的命令行工具。
# Cilium 是一个为 Kubernetes 提供的 CNI，它可以提供安全的网络连接和负载均衡，并利用 eBPF 提供出色的可视化功能。
# 用法:
#   cilium [flags]
#   cilium [command]
# 示例:
# cilium install # 在当前的 Kubernetes 上下文中安装 Cilium
# cilium install --dry-run-helm-values # 查看所有与 Cilium 相关的资源，而无需将它们安装到集群中
# cilium status # 检查 Cilium 的状态
# cilium hubble enable # 启用 Hubble 观察层
# cilium connectivity test # 执行连接测试
# 可用命令:
#   bgp          访问 BGP 控制平面
#   clustermesh  多集群管理
#   completion   为指定的 shell 生成自动补全脚本
#   config       管理配置
#   connectivity 连接故障排除
#   context      显示配置上下文
#   help         关于任何命令的帮助
#   hubble       Hubble 观察性
#   install      使用 Helm 在 Kubernetes 集群中安装 Cilium
#   status       显示状态
#   sysdump      收集排查 Cilium 和 Hubble 问题所需的信息
#   uninstall    使用 Helm 卸载 Cilium
#   upgrade      使用 Helm 在 Kubernetes 集群中升级 Cilium 安装
#   version      显示详细的版本信息
# 标志:
#       --context string     Kubernetes 配置上下文
#   -h, --help               cilium 帮助
#   -n, --namespace string   Cilium 运行的命名空间（默认为 "kube-system"）

# Helm
curl -LO https://github.com/cilium/cilium/archive/main.tar.gz

# https://github.com/cilium/cilium-cli
# helm list -n kube-system --filter "cilium" # 查看已部署的 Helm 版本
# helm get values -n kube-system cilium # 在不实际执行安装的情况下查看所有非默认 Helm 值

#--version 1.12.0 \
#--set hubble.Ui.Backend.Image.Tag=v0.9.0  \
#--set hubble.ui.Frontend.Image.Tag=v0.9.0 \

# annotateK8sNode: 在初始化时使用 Cilium 的元数据注释 k8s 节点。
# sctp.enabled: 启用 SCTP 支持。注意:目前，SCTP 支持不支持重写端口或多宿主。SCTP（Stream Control Transmission Protocol）是一种传输层协议，它提供了可靠的、面向消息的、多路复用的传输。SCTP 最初是为了在电话网络中传输信令信息而设计的，但现在也被广泛用于 IP 网络中。SCTP 具有许多优点，包括提供了比 TCP 更好的消息边界保护、抗拒绝服务攻击（DoS）的能力以及多宿主连接。SCTP 还支持多条流，这使得它非常适合于一些需要同时传输多个消息的应用程序
# kubeProxyReplacementHealthzBindAddr: healthz 服务器绑定地址，用于 kube-proxy 替换。若要启用，请将所有 ipv4 地址的值设置为“0.0.0.0:10256”，将所有 ipv6 地址的值设置为“[::]:10256”。默认情况下，它处于禁用状态。
# k8sServiceHost: Kubernetes 服务主机
# k8sservicePort: 端口
# ipam.Operator.ClusterPoolIPv4MaskSize: IPv4 CIDR 掩码大小，以委派给 IPAM 的各个节点。
# tunnel: 配置节点间通信的封装配置。弃用了 tunnelProtocol 和 routingMode。将在 1.15 中删除。可能的值: - disabled - vxlan - geneve
# routingMode: 启用本机路由模式或隧道模式,默认值:tunnel,  可能的值: "" - native - tunnel
# ipv4NativeRoutingCIDR: Pod的网段. 允许显式指定本机路由的 IPv4 CIDR。指定后，Cilium 假定此 CIDR 的网络已预先配置，并将发往该范围的流量传递给 Linux 网络堆栈，而不应用任何 SNAT。一般来说，指定本机路由 CIDR 意味着 Cilium 可以依赖底层网络堆栈将数据包路由到其目的地。举个具体的例子，如果 Cilium 配置为使用直接路由，并且 Kubernetes CIDR 包含在原生路由 CIDR 中，则用户必须手动或通过设置 auto-direct-node-routes 标志来配置路由以访问 Pod。
# bpf.masquerade: 在 eBPF 中启用原生 IP 伪装支持
# ipam.mode: 配置 IP 地址管理模式,https://docs.cilium.io/en/stable/network/concepts/ipam
# hubble.Enabled: 启用 Hubble默认为 true
# hubble.Relay.Enabled: 启用 Hubble Relay（需要 hubble.enabled=true）
# hubble.Ui.Enabled 启用UI
# envoy.prometheus.enabled: 为 cilium-envoy 启用 prometheus 指标
# operator.prometheus: 在 /metrics 处配置的端口上为 cilium-operator 启用 prometheus 指标
# operator.prometheus.serviceMonitor.annotations: 要添加到 ServiceMonitor cilium-operator 的注解
# operator.prometheus.serviceMonitor.enabled: 启用服务监视器。这需要 prometheus CRD 可用（参见 https://github.com/prometheus-operator/prometheus-operator/blob/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
# perator.prometheus.serviceMonitor.interval: 抓取指标间隔
# hubble.Metrics.Enabled: 配置要收集的指标列表。如果为空或 null，则禁用指标。示例: enabled: - dns:query;ignoreAAAA - drop - tcp - flow - icmp - http 您可以从 helm CLI 指定指标列表: –set metrics.enabled="{dns:query;ignoreAAAA,drop,tcp,flow,icmp,http}"

# --set k8sServiceHost=192.168.2.152 \
#helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.14.5 \
--namespace kube-system \
--reuse-values \
--set hubble.relay.enabled=true \
--set hubble.ui.enabled=true \
--set k8sServiceHost=master-node-152 \
--set k8sservicePort=6443 \

# P9s Ga
# https://docs.cilium.io/en/stable/observability/grafana/
helm install cilium cilium/cilium \
--version 1.14.5 \
--namespace kube-system \
--set prometheus.enabled=true \
--set operator.prometheus.enabled=true \
--set hubble.enabled=true \
--set hubble.metrics.enableOpenMetrics=true \
--set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"

# Grafana
# kubectl -n cilium-monitoring port-forward service/grafana --address 0.0.0.0 --address :: 3000:3000

# Prometheus
# kubectl -n cilium-monitoring port-forward service/prometheus --address 0.0.0.0 --address :: 9090:9090

# test 1
helm install cilium cilium/cilium \
--version 1.14.5 \
--namespace kube-system \
--set kubeProxyReplacement=true \
--set annotateK8sNode=true \
--set tunnel=disabled \
--set routingMode=native \
--set ipv4NativeRoutingCIDR=10.244.0.0/16 \
--set loadBalancer.mode=dsr \
--set loadBalancer.dsrDispatch=opt \
--set ipMasqAgent.enabled=true \
--set bpf.masquerade=true \
--set ipam.mode=kubernetes \
--set ipam.operator.clusterPoolIPv4PodCIDRList=10.244.0.0/16 \
--set ipam.operator.clusterPoolIPv4MaskSize=24 \
--set k8sServiceHost=master-node-152 \
--set k8sServicePort=6443 \
--set hubble.relay.enabled=true \
--set hubble.ui.enabled=true

#helm install cilium cilium/cilium \
#--version 1.14.5 \
#--namespace kube-system \
#--set kubeProxyReplacement=true \
#--set k8sServiceHost=master-node-152 \
#--set k8sservicePort=6443 \
#--set ipam.mode=kubernetes \
#--set ipam.Operator.clusterPoolIPv4PodCIDRList=["10.244.0.0/16"] \
#--set ipam.Operator.ClusterPoolIPv4MaskSize=24 \
#--set hubble.Enabled=true  \
#--set hubble.relay.enabled=true \
#--set hubble.ui.enabled=true
#--set hubble.Metrics.Enabled="{dns, drop, tcp, flow, port-distribution, icmp, http}"  \
#--set annotateK8sNode=true \
#--set sctp.enabled=true \
#--set tunnel=disabled \
#--set routingMode=native \
#--set ipv4NativeRoutingCIDR=10.244.0.0/16 \
#--set bpf.masquerade=true

# 验证安装
kubectl -n kube-system get pods -l k8s-app=cilium

set +x
