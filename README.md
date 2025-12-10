# VPS 一键脚本合集
本文整理两款 Linux 系统 VPS 常用一键脚本，包含 Docker 相关脚本与 DNS 修改脚本，支持直接复制命令执行。

## 1. Docker 万能脚本
一键下载并执行 GitHub 仓库中的 `dockerwanneng.sh` 脚本，快速完成 Docker 相关配置：

### 推荐版本（wget 下载）
```bash
wget -O dockerwanneng.sh https://raw.githubusercontent.com/shiliandeai/vpsgongk/main/dockerwanneng.sh && chmod +x dockerwanneng.sh && ./dockerwanneng.sh

wget -O dns.sh https://raw.githubusercontent.com/shiliandeai/vpsgongk/main/dns.sh && chmod +x dns.sh && ./dns.sh
