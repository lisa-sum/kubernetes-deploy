#!/bin/sh

set -x

# 查看cgroup
# 获取文件系统类型
filesystem_type=$(stat -fc %T /sys/fs/cgroup)

# 判断文件系统类型是否为 cgroup2fs
# 对于 cgroup v2，输出为 `cgroup2fs`。
# 对于 cgroup v1，输出为 `tmpfs`。
if [ "$filesystem_type" != "cgroup2fs" ]; then
   # 更新到 cgroup2(Ubuntu20.x)
   sudo grubby \
     --update-kernel=ALL \
     --args="systemd.unified_cgroup_hierarchy=1"
fi

# 如果文件系统类型为 cgroup2fs，执行后续操作
echo "文件系统类型为 cgroup2fs，执行后续操作。"

# 手动重启
sudo reboot

# 重启containerd
sudo systemctl restart containerd

set +x
