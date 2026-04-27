#!/bin/bash
# ============================================================
# PlayEdu 一键部署脚本 (Rocky Linux 10)
# 用法: sudo bash deploy/install.sh
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置变量
INSTALL_DIR="/opt/playedu"
FRONTEND_DIR="/opt/playedu/frontend"
CURRENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MYSQL_ROOT_PASS="playeduxyz"
DB_NAME="playedu"
DB_USER="root"
DB_PASS="playeduxyz"

# MinIO 配置
MINIO_ACCESS_KEY="playedu"
MINIO_SECRET_KEY="playedu123"
MINIO_BUCKET="playedu"
MINIO_DATA_DIR="/opt/minio/data"
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001

# 获取本机 IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

# ---- 交互式配置 ----
echo -e "${YELLOW}请确认以下配置（直接回车使用默认值）:${NC}"
echo ""

read -p "  MinIO 数据存储目录 [${MINIO_DATA_DIR}]: " INPUT_MINIO_DIR
MINIO_DATA_DIR="${INPUT_MINIO_DIR:-${MINIO_DATA_DIR}}"
# 去除末尾斜杠
MINIO_DATA_DIR="${MINIO_DATA_DIR%/}"

read -p "  MinIO API 端口 [${MINIO_PORT}]: " INPUT_MINIO_PORT
MINIO_PORT="${INPUT_MINIO_PORT:-${MINIO_PORT}}"

read -p "  MinIO 管理界面端口 [${MINIO_CONSOLE_PORT}]: " INPUT_MINIO_CONSOLE
MINIO_CONSOLE_PORT="${INPUT_MINIO_CONSOLE:-${MINIO_CONSOLE_PORT}}"

read -p "  MinIO 管理账号 [${MINIO_ACCESS_KEY}]: " INPUT_MINIO_AK
MINIO_ACCESS_KEY="${INPUT_MINIO_AK:-${MINIO_ACCESS_KEY}}"

read -p "  MinIO 管理密码 [${MINIO_SECRET_KEY}]: " INPUT_MINIO_SK
MINIO_SECRET_KEY="${INPUT_MINIO_SK:-${MINIO_SECRET_KEY}}"

read -p "  MySQL 数据库密码 [${DB_PASS}]: " INPUT_DB_PASS
DB_PASS="${INPUT_DB_PASS:-${DB_PASS}}"

echo ""
echo -e "${GREEN}配置确认:${NC}"
echo "  MinIO 数据目录:  ${MINIO_DATA_DIR}"
echo "  MinIO API 端口:   ${MINIO_PORT}"
echo "  MinIO 管理端口:   ${MINIO_CONSOLE_PORT}"
echo "  MinIO 管理账号:   ${MINIO_ACCESS_KEY}"
echo "  MinIO 管理密码:   ${MINIO_SECRET_KEY}"
echo "  MySQL 密码:       ${DB_PASS}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  PlayEdu 非 Docker 部署 - Rocky Linux 10${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行此脚本: sudo bash deploy/install.sh${NC}"
    exit 1
fi

# ---- 1. 安装基础依赖 ----
echo -e "${YELLOW}[1/9] 安装基础依赖...${NC}"

# 更新系统
dnf update -y

# 安装 EPEL 和必要工具
dnf install -y epel-release
dnf install -y git wget curl tar which unzip

# Rocky Linux 10: 启用 CRB 仓库（OpenJDK 17 在 CRB 中）
dnf config-manager --set-enabled crb || dnf config-manager --set-enabled powertools || true

# 安装 JDK 17
echo -e "${YELLOW}  安装 JDK 17...${NC}"
if ! java -version 2>&1 | grep -q "17"; then
    dnf install -y java-17-openjdk java-17-openjdk-devel || {
        echo -e "${YELLOW}  CRB 仓库中未找到 JDK 17，尝试安装 JDK 21...${NC}"
        dnf install -y java-21-openjdk java-21-openjdk-devel || {
            echo -e "${RED}  无法通过 dnf 安装 JDK，尝试手动安装...${NC}"
            cd /tmp
            wget -q "https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.tar.gz" -O jdk17.tar.gz || \
            wget -q "https://corretto.aws/downloads/latest/amazon-corretto-17-x64-linux-jdk.tar.gz" -O jdk17.tar.gz || {
                echo -e "${RED}  JDK 下载失败，请手动安装 JDK 17 后重试${NC}"
                exit 1
            }
            mkdir -p /usr/lib/jvm/jdk-17
            tar xzf jdk17.tar.gz -C /usr/lib/jvm/jdk-17 --strip-components=1
            rm -f jdk17.tar.gz
            alternatives --install /usr/bin/java java /usr/lib/jvm/jdk-17/bin/java 100
            alternatives --install /usr/bin/javac javac /usr/lib/jvm/jdk-17/bin/javac 100
            export JAVA_HOME=/usr/lib/jvm/jdk-17
            export PATH=$JAVA_HOME/bin:$PATH
            echo "export JAVA_HOME=/usr/lib/jvm/jdk-17" > /etc/profile.d/java.sh
            echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/java.sh
            source /etc/profile.d/java.sh
        }
    }
fi
echo "  Java 版本: $(java -version 2>&1 | head -1)"

# 安装 Maven
echo -e "${YELLOW}  安装 Maven...${NC}"
if ! command -v mvn &> /dev/null; then
    dnf install -y maven || {
        echo -e "${YELLOW}  dnf 未找到 maven，手动安装...${NC}"
        cd /tmp
        MAVEN_VER="3.9.9"
        wget -q "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VER}/binaries/apache-maven-${MAVEN_VER}-bin.tar.gz" -O maven.tar.gz
        tar xzf maven.tar.gz -C /opt/
        rm -f maven.tar.gz
        ln -sf /opt/apache-maven-${MAVEN_VER}/bin/mvn /usr/bin/mvn
    }
fi
echo "  Maven 版本: $(mvn -version 2>&1 | head -1)"

# 安装 MySQL 8（Rocky Linux 10 的 mysql-server 实际为 MariaDB）
echo -e "${YELLOW}  安装 MySQL/MariaDB...${NC}"
if ! command -v mysql &> /dev/null; then
    dnf install -y mysql-server || dnf install -y mariadb-server
fi
systemctl enable mariadb 2>/dev/null || true
systemctl start mariadb 2>/dev/null || systemctl start mysqld 2>/dev/null || true

# 安装 Node.js
echo -e "${YELLOW}  安装 Node.js...${NC}"
if ! command -v node &> /dev/null; then
    dnf install -y nodejs npm 2>/dev/null || {
        echo -e "${YELLOW}  dnf 未找到 nodejs，通过 NodeSource 安装...${NC}"
        dnf install -y curl ca-certificates
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
        dnf install -y nodejs
    }
fi
echo "  Node.js 版本: $(node -v)"

# 安装 pnpm
echo -e "${YELLOW}  安装 pnpm...${NC}"
if ! command -v pnpm &> /dev/null; then
    npm install -g pnpm
fi
echo "  pnpm 版本: $(pnpm -v)"

# 安装 Nginx
echo -e "${YELLOW}  安装 Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    dnf install -y nginx
    systemctl enable nginx
fi
echo "  Nginx 版本: $(nginx -v 2>&1)"

echo -e "${GREEN}  基础依赖安装完成!${NC}"

# ---- 2. 配置 MySQL ----
echo -e "${YELLOW}[2/9] 配置 MySQL...${NC}"

cp "${CURRENT_DIR}/deploy/mysql/playedu.cnf" /etc/my.cnf.d/playedu.cnf

if systemctl list-unit-files mariadb.service &>/dev/null; then
    MYSQL_SVC="mariadb"
else
    MYSQL_SVC="mysqld"
fi
systemctl restart ${MYSQL_SVC}

for i in $(seq 1 30); do
    if mysqladmin ping -u root --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true

mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_PASS}'); FLUSH PRIVILEGES;" 2>/dev/null || \
mysql -u root -p"${DB_PASS}" -e "SELECT 1" 2>/dev/null || true

echo -e "${GREEN}  MySQL 配置完成!${NC}"

# ---- 3. 部署 MinIO 对象存储 ----
echo -e "${YELLOW}[3/9] 部署 MinIO 对象存储...${NC}"

if ! command -v minio &> /dev/null; then
    echo -e "${YELLOW}  下载 MinIO...${NC}"
    wget -q https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
    chmod +x /usr/local/bin/minio
fi

# 创建数据目录
mkdir -p "${MINIO_DATA_DIR}"

# 创建 systemd 服务
cat > /etc/systemd/system/minio.service << MINIOEOF
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
User=root
Environment="MINIO_ROOT_USER=${MINIO_ACCESS_KEY}"
Environment="MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}"
ExecStart=/usr/local/bin/minio server ${MINIO_DATA_DIR} --console-address ":${MINIO_CONSOLE_PORT}"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
MINIOEOF

systemctl daemon-reload
systemctl enable minio
systemctl restart minio

# 等待 MinIO 启动
for i in $(seq 1 15); do
    if curl -s http://127.0.0.1:${MINIO_PORT}/minio/health/live > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 安装 mc 客户端并创建 Bucket
echo -e "${YELLOW}  配置 MinIO Bucket...${NC}"
if ! command -v mc &> /dev/null; then
    wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
    chmod +x /usr/local/bin/mc
fi

# 配置 mc 连接本地 MinIO
mc alias set localminio http://127.0.0.1:${MINIO_PORT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} > /dev/null 2>&1 || true

# 创建 Bucket（如果不存在）
mc mb localminio/${MINIO_BUCKET} --ignore-existing 2>/dev/null || true

# 设置 Bucket 为私有（PlayEdu 要求）
mc anonymous set none localminio/${MINIO_BUCKET} 2>/dev/null || true

echo -e "${GREEN}  MinIO 部署完成!${NC}"
echo -e "${GREEN}    API 地址: http://${LOCAL_IP}:${MINIO_PORT}${NC}"
echo -e "${GREEN}    管理界面: http://${LOCAL_IP}:${MINIO_CONSOLE_PORT}${NC}"
echo -e "${GREEN}    管理账号: ${MINIO_ACCESS_KEY} / ${MINIO_SECRET_KEY}${NC}"

# ---- 4. 复制源码到安装目录 ----
echo -e "${YELLOW}[4/9] 部署源码到 ${INSTALL_DIR}...${NC}"
mkdir -p "${INSTALL_DIR}"
cp -r "${CURRENT_DIR}/playedu-api" "${INSTALL_DIR}/"
cp -r "${CURRENT_DIR}/playedu-admin" "${INSTALL_DIR}/"
cp -r "${CURRENT_DIR}/playedu-pc" "${INSTALL_DIR}/"
cp -r "${CURRENT_DIR}/playedu-h5" "${INSTALL_DIR}/"
cp -r "${CURRENT_DIR}/deploy" "${INSTALL_DIR}/"
echo -e "${GREEN}  源码部署完成!${NC}"

# ---- 5. 构建后端 ----
echo -e "${YELLOW}[5/9] 构建后端 API...${NC}"
cd "${INSTALL_DIR}/playedu-api"
chmod +x mvnw
./mvnw clean package -Dmaven.test.skip=true
echo -e "${GREEN}  后端构建完成!${NC}"

# ---- 6. 构建前端 ----
echo -e "${YELLOW}[6/9] 构建前端项目...${NC}"

echo "  构建 playedu-admin..."
cd "${INSTALL_DIR}/playedu-admin"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build

echo "  构建 playedu-pc..."
cd "${INSTALL_DIR}/playedu-pc"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build

echo "  构建 playedu-h5..."
cd "${INSTALL_DIR}/playedu-h5"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build

echo -e "${GREEN}  前端构建完成!${NC}"

# ---- 7. 部署前端静态文件 ----
echo -e "${YELLOW}[7/9] 部署前端静态文件...${NC}"
mkdir -p "${FRONTEND_DIR}"
cp -r "${INSTALL_DIR}/playedu-admin/dist" "${FRONTEND_DIR}/admin"
cp -r "${INSTALL_DIR}/playedu-pc/dist" "${FRONTEND_DIR}/pc"
cp -r "${INSTALL_DIR}/playedu-h5/dist" "${FRONTEND_DIR}/h5"
chmod -R 755 "${FRONTEND_DIR}"
echo -e "${GREEN}  静态文件部署完成!${NC}"

# ---- 8. 配置 Nginx ----
echo -e "${YELLOW}[8/9] 配置 Nginx...${NC}"
cp "${INSTALL_DIR}/deploy/nginx/playedu.conf" /etc/nginx/conf.d/playedu.conf
rm -f /etc/nginx/conf.d/default.conf

# SELinux: 允许 Nginx 绑定非标准端口
if command -v semanage &> /dev/null && getenforce 2>/dev/null | grep -q "Enforcing"; then
    echo -e "${YELLOW}  配置 SELinux 端口放行...${NC}"
    for PORT in 9800 9801 9900; do
        semanage port -l | grep -q "http_port_t.*${PORT}" || \
            semanage port -a -t http_port_t -p tcp ${PORT} 2>/dev/null || true
    done
    echo -e "${GREEN}  SELinux 端口放行完成!${NC}"
fi

nginx -t
systemctl restart nginx
echo -e "${GREEN}  Nginx 配置完成!${NC}"

# ---- 9. 自动写入 S3 存储配置到数据库 ----
echo -e "${YELLOW}[9/9] 配置 S3 存储连接...${NC}"
echo -e "${YELLOW}  等待后端首次启动以初始化数据库表结构...${NC}"

# 启动后端（首次启动会自动建表和初始化配置）
cd "${INSTALL_DIR}/playedu-api"
nohup java -jar playedu-api/target/playedu-api.jar --spring.profiles.active=dev > /tmp/playedu-init.log 2>&1 &
INIT_PID=$!

# 等待后端启动完成
for i in $(seq 1 60); do
    if curl -s http://127.0.0.1:9898/api/v1/system/config > /dev/null 2>&1; then
        break
    fi
    if ! kill -0 $INIT_PID 2>/dev/null; then
        echo -e "${RED}  后端启动失败，请查看日志: /tmp/playedu-init.log${NC}"
        exit 1
    fi
    sleep 2
done

# 验证后端是否就绪
if ! curl -s http://127.0.0.1:9898/api/v1/system/config > /dev/null 2>&1; then
    echo -e "${YELLOW}  后端仍在初始化中，S3 配置将在后端就绪后自动写入...${NC}"
else
    # 写入 S3 存储配置到数据库
    MINIO_ENDPOINT="http://${LOCAL_IP}:${MINIO_PORT}"
    mysql -u root -p"${DB_PASS}" ${DB_NAME} << SQLEOF
UPDATE app_config SET key_value='${MINIO_ACCESS_KEY}' WHERE key_name='s3.access_key';
UPDATE app_config SET key_value='${MINIO_SECRET_KEY}' WHERE key_name='s3.secret_key';
UPDATE app_config SET key_value='${MINIO_BUCKET}' WHERE key_name='s3.bucket';
UPDATE app_config SET key_value='us-east-1' WHERE key_name='s3.region';
UPDATE app_config SET key_value='${MINIO_ENDPOINT}' WHERE key_name='s3.endpoint';
UPDATE app_config SET key_value='${MINIO_ENDPOINT}' WHERE key_name='s3.domain';
SQLEOF
    echo -e "${GREEN}  S3 存储配置已自动写入!${NC}"
fi

# 停止初始化用的后端进程
kill $INIT_PID 2>/dev/null || true
sleep 2

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  部署完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  后续操作:"
echo "    1. 启动所有服务: sudo bash ${INSTALL_DIR}/deploy/playedu.sh start"
echo "    2. 停止所有服务: sudo bash ${INSTALL_DIR}/deploy/playedu.sh stop"
echo "    3. 查看后端日志:  sudo bash ${INSTALL_DIR}/deploy/playedu.sh log"
echo "    4. 查看 MinIO:   浏览器打开 http://${LOCAL_IP}:${MINIO_CONSOLE_PORT}"
echo ""
echo "  访问地址:"
echo -e "    ${GREEN}管理后台:${NC}  http://${LOCAL_IP}:9900"
echo -e "    ${GREEN}PC 学员端:${NC} http://${LOCAL_IP}:9800"
echo -e "    ${GREEN}H5 移动端:${NC} http://${LOCAL_IP}:9801"
echo -e "    ${GREEN}MinIO 管理:${NC} http://${LOCAL_IP}:${MINIO_CONSOLE_PORT}"
echo ""
echo "  默认管理员账号: admin@playedu.xyz / playedu"
echo "  MinIO 账号: ${MINIO_ACCESS_KEY} / ${MINIO_SECRET_KEY}"
echo "  (请登录后立即修改密码!)"
echo ""
