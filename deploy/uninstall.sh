#!/bin/bash
# ============================================================
# PlayEdu 卸载清理脚本
# 用法: sudo bash deploy/uninstall.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}  PlayEdu 卸载清理${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}此操作将删除 PlayEdu 及 MinIO 的所有数据，不可恢复！${NC}"
read -p "确认卸载？(输入 yes 继续): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "已取消。"
    exit 0
fi
echo ""

# 1. 停止所有服务
echo -e "${YELLOW}[1/7] 停止所有服务...${NC}"
sudo bash /opt/playedu/deploy/playedu.sh stop 2>/dev/null || true
sudo systemctl stop playedu 2>/dev/null || true
sudo systemctl stop minio 2>/dev/null || true
sudo systemctl stop nginx 2>/dev/null || true

# 2. 禁用并删除 systemd 服务
echo -e "${YELLOW}[2/7] 删除 systemd 服务...${NC}"
sudo systemctl disable minio 2>/dev/null || true
sudo systemctl disable playedu 2>/dev/null || true
sudo rm -f /etc/systemd/system/minio.service
sudo rm -f /etc/systemd/system/playedu.service
sudo systemctl daemon-reload

# 3. 删除 Nginx 配置
echo -e "${YELLOW}[3/7] 删除 Nginx 配置...${NC}"
sudo rm -f /etc/nginx/conf.d/playedu.conf
sudo systemctl restart nginx 2>/dev/null || true

# 4. 删除应用和数据
echo -e "${YELLOW}[4/7] 删除应用和数据...${NC}"
sudo rm -rf /opt/playedu
sudo rm -rf /opt/minio
sudo rm -f /var/run/playedu.pid
sudo rm -f /var/log/playedu.log
sudo rm -f /tmp/playedu-init.log

# 5. 删除数据库
echo -e "${YELLOW}[5/7] 删除数据库...${NC}"
mysql -u root -pplayeduxyz -e "DROP DATABASE IF EXISTS playedu;" 2>/dev/null || \
mysql -u root -e "DROP DATABASE IF EXISTS playedu;" 2>/dev/null || \
echo -e "${YELLOW}  无法连接数据库，请手动删除 playedu 数据库${NC}"

# 6. 删除源码包
echo -e "${YELLOW}[6/7] 删除源码包...${NC}"
rm -rf ~/playedu
rm -rf /tmp/playedu-*.tar.gz

# 7. 删除 MySQL 字符集配置
echo -e "${YELLOW}[7/7] 删除 MySQL 配置...${NC}"
sudo rm -f /etc/my.cnf.d/playedu.cnf

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  清理完成!${NC}"
echo -e "${GREEN}========================================${NC}"
