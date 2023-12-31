#!/bin/sh

set -x

# 自动化: https://kubernetes.io/zh-cn/docs/reference/setup-tools/kubeadm/kubeadm-init/#automating-kubeadm
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
