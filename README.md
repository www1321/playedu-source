# PlayEdu 源码一键部署版

> 基于 [PlayEdu](https://github.com/PlayEdu/PlayEdu) 的非 Docker 源码部署方案，针对 Rocky Linux 10 深度适配，集成 MinIO 本地对象存储，一键完成全部环境搭建与应用部署。

---

## 目录

- [与 Docker 版的差异](#与-docker-版的差异)
- [快速开始](#快速开始)
- [服务管理](#服务管理)
- [关键配置](#关键配置)
- [常见报错排查](#常见报错排查)
- [卸载](#卸载)

---

## 与 Docker 版的差异

| 对比项 | Docker 版（官方） | 源码一键部署版（本仓库） |
|--------|-------------------|------------------------|
| **部署方式** | `docker compose up -d` | `bash deploy/install.sh` |
| **运行环境** | 全部容器化，依赖 Docker Engine | 直接运行在宿主机，无容器依赖 |
| **数据库** | Docker 内 MySQL 8 容器 | 宿主机 MariaDB（Rocky Linux 10 自带） |
| **前端部署** | 内置在 Java 容器中，由后端 serve | Nginx 独立提供静态文件服务 |
| **对象存储** | 需自行配置外部 S3 | 内置 MinIO，一键自动部署 |
| **API 端口** | 默认对外 9700 | 直接 9898（Nginx 代理后前端无感） |
| **配置方式** | `.env` + `compose.yml` | `application-dev.yml` + `.env` + Nginx conf |
| **字符集兼容** | MySQL 8 原生 `utf8mb4_0900_ai_ci` | 已改为 `utf8mb4_unicode_ci`（MariaDB 兼容） |
| **资源占用** | Docker 引擎额外开销 | 更轻量 |
| **调试便利** | 需进入容器查看日志 | 直接访问日志文件，原生调试体验 |

**关键代码修改：** `playedu-system/.../MigrationCheck.java` 中 LDAP 相关表的 `COLLATE utf8mb4_0900_ai_ci` → `utf8mb4_unicode_ci`（MariaDB 不支持 MySQL 8.0 的 0900 排序规则）

---

## 快速开始

### 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Rocky Linux 10 / RHEL 10 / CentOS Stream 10（x86_64） |
| 内存 | ≥ 4GB（推荐 8GB） |
| 磁盘 | ≥ 20GB（不含课程视频存储） |
| 网络 | 需要访问外网（安装依赖和下载 MinIO） |
| 权限 | root 或 sudo |

> 其他 Linux 发行版（Ubuntu 22.04/24.04、Debian 12）也可使用，需将 `dnf` 替换为 `apt`。

### 一键部署

```bash
git clone https://github.com/www1321/playedu-source.git
cd playedu-source
sudo bash deploy/install.sh
```

脚本自动完成 9 步：安装依赖 → 配置 MariaDB → 部署 MinIO → 复制源码 → 编译后端 → 编译前端 → 部署静态文件 → 配置 Nginx → 自动建表并写入 S3 配置。

部署过程中可交互式配置（直接回车使用默认值）：

```
  MinIO 数据存储目录 [/opt/minio/data]:
  MinIO API 端口 [9000]:
  MinIO 管理界面端口 [9001]:
  MinIO 管理账号 [playedu]:
  MinIO 管理密码 [playedu123]:
  MySQL 数据库密码 [playeduxyz]:
```

### 启动与访问

```bash
sudo bash /opt/playedu/deploy/playedu.sh start
```

| 服务 | 地址 | 默认账号 |
|------|------|----------|
| 管理后台 | `http://YOUR_IP:9900` | `admin@playedu.xyz` / `playedu` |
| PC 学员端 | `http://YOUR_IP:9800` | 前台注册 |
| H5 移动端 | `http://YOUR_IP:9801` | 前台注册 |
| MinIO 管理 | `http://YOUR_IP:9001` | 部署时设置 |

> ⚠️ 请登录后立即修改默认密码！

### 防火墙放行

```bash
sudo firewall-cmd --permanent --add-port={9800,9801,9900}/tcp
sudo firewall-cmd --reload
```

---

## 服务管理

```bash
sudo bash /opt/playedu/deploy/playedu.sh <命令>
```

| 命令 | 说明 |
|------|------|
| `start` | 启动后端（自动启动 MinIO） |
| `stop` | 停止后端 |
| `restart` | 重启后端 |
| `status` | 查看所有服务状态 + 端口监听 |
| `log` | 实时查看后端日志 |
| `build` | 重新编译后端 |
| `build-fe` | 重新编译前端并部署 |

### 注册为 systemd 服务（可选）

```bash
sudo cp /opt/playedu/deploy/systemd/playedu.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable playedu
# 之后使用 systemctl 管理
sudo systemctl status/restart playedu
journalctl -u playedu -f
```

### 端口汇总

| 端口 | 服务 |
|------|------|
| 9898 | PlayEdu API |
| 9800 | PC 学员端 |
| 9801 | H5 移动端 |
| 9900 | 管理后台 |
| 9000 | MinIO API |
| 9001 | MinIO Console |
| 3306 | MariaDB |

---

## 关键配置

只需关注以下配置文件，其余均已预置默认值：

### 修改数据库密码

编辑 `playedu-api/playedu-api/src/main/resources/application-dev.yml`：

```yaml
spring:
  datasource:
    url: "jdbc:mysql://127.0.0.1:3306/playedu?useUnicode=true&characterEncoding=UTF-8&autoReconnect=true&useSSL=false&allowPublicKeyRetrieval=true"
    username: "root"
    password: "你的密码"
```

修改后需重新构建并重启：

```bash
sudo bash /opt/playedu/deploy/playedu.sh build && sudo bash /opt/playedu/deploy/playedu.sh restart
```

### 修改 S3 存储配置

存储配置存储在数据库 `app_config` 表中，部署脚本已自动写入：

```sql
-- 查看当前配置
SELECT key_name, key_value FROM playedu.app_config WHERE key_name LIKE 's3.%';

-- 修改（如更换 IP）
UPDATE playedu.app_config SET key_value='http://新IP:9000' WHERE key_name='s3.endpoint';
```

> `s3.region` 不可为空，MinIO 使用 `us-east-1`。修改后需重启后端。

### 其他配置文件（一般不需要修改）

| 文件 | 作用 |
|------|------|
| `playedu-api/.../application.yml` | 后端主配置（端口、JWT 密钥、连接池、限流） |
| `playedu-admin/.env` / `playedu-pc/.env` / `playedu-h5/.env` | 前端 API 地址（`VITE_APP_URL=/api/`） |
| `deploy/nginx/playedu.conf` | Nginx 反向代理（`/api/` → 后端，SPA 路由回退） |
| `deploy/mysql/playedu.cnf` | MariaDB 字符集（utf8mb4） |

---

## 常见报错排查

### 后端启动失败

```bash
# 查看日志
sudo bash /opt/playedu/deploy/playedu.sh log
# 或
sudo tail -100 /var/log/playedu.log
```

| 报错 | 原因 | 解决 |
|------|------|------|
| `Communications link failure` | 数据库未启动 | `sudo systemctl start mariadb` |
| `Unknown database 'playedu'` | 数据库未创建 | `mysql -u root -p -e "CREATE DATABASE playedu DEFAULT CHARACTER SET utf8mb4;"` |
| `Access denied for user 'root'@'localhost'` | 密码不匹配 | 检查 `application-dev.yml` 与数据库密码一致 |
| `Port 9898 already in use` | 端口占用 | `ss -tlnp \| grep 9898` 查看并终止 |
| `Unknown collation 'utf8mb4_0900_ai_ci'` | MariaDB 不兼容 | 确认使用本仓库修改过的源码 |

### 前端页面空白或 502

```bash
sudo systemctl status nginx          # Nginx 是否运行
sudo nginx -t                        # 配置是否正确
curl http://127.0.0.1:9898/api/v1/system/config  # 后端是否正常
ls /opt/playedu/frontend/admin/      # 静态文件是否存在
```

### Nginx 端口绑定失败

```
bind() to 0.0.0.0:9800 failed (13: Permission denied)
```

SELinux 阻止了非标准端口：

```bash
getenforce  # 确认 SELinux 状态
sudo semanage port -a -t http_port_t -p tcp 9800
sudo semanage port -a -t http_port_t -p tcp 9801
sudo semanage port -a -t http_port_t -p tcp 9900
sudo systemctl restart nginx
```

### 上传报"存储服务未配置"

`s3.region` 为空导致，代码中 3 处校验要求 region 非空：

```sql
-- 排查
SELECT key_name, key_value FROM playedu.app_config WHERE key_name LIKE 's3.%';
-- 修复
UPDATE playedu.app_config SET key_value='us-east-1' WHERE key_name='s3.region';
```

### MinIO 无法访问

```bash
sudo systemctl status minio                           # 服务状态
sudo journalctl -u minio -n 50 --no-pager             # 日志
ss -tlnp | grep -E '9000|9001'                        # 端口监听
curl http://127.0.0.1:9000/minio/health/live          # 连通性测试
ls -la /opt/minio/data/                                # 数据目录权限
```

### JDK 安装失败

Rocky Linux 10 的 JDK 17 在 CRB 仓库中：

```bash
sudo dnf config-manager --set-enabled crb
sudo dnf install -y java-17-openjdk java-17-openjdk-devel
```

部署脚本已内置三级回退：CRB 仓库 → JDK 21 → 手动下载。

### MariaDB 服务名冲突

Rocky Linux 10 中 `mysql-server` 实际是 MariaDB，`mysqld.service` 是符号链接：

```
Failed to enable unit: Refusing to operate on linked unit file
```

**始终使用 `mariadb` 作为服务名：**

```bash
sudo systemctl start/enable/status mariadb
```

### 数据库连接池耗尽

```
HikariPool-1 - Connection is not available, request timed out
```

修改 `application.yml` 中 `hikari.maximum-pool-size`（默认 10），改后需重新构建。

---

## 卸载

```bash
sudo bash /opt/playedu/deploy/uninstall.sh
```

清理所有服务、数据、数据库（需输入 `yes` 确认，不可逆）。

---

## 目录结构

```
playedu-source/
├── deploy/                          # 部署工具
│   ├── install.sh                   # 一键部署
│   ├── playedu.sh                   # 服务管理
│   ├── uninstall.sh                 # 卸载清理
│   ├── nginx/playedu.conf           # Nginx 配置
│   ├── mysql/playedu.cnf            # MySQL 字符集
│   └── systemd/playedu.service      # systemd 服务
├── playedu-api/                     # 后端（Spring Boot 多模块）
│   ├── playedu-api/                 #   API 入口
│   ├── playedu-common/              #   公共模块
│   ├── playedu-system/              #   系统模块
│   ├── playedu-course/              #   课程模块
│   └── playedu-resource/            #   资源模块
├── playedu-admin/                   # 管理后台（React + Ant Design）
├── playedu-pc/                      # PC 学员端（React）
├── playedu-h5/                      # H5 移动端（React）
├── LICENSE                          # AGPL-3.0
└── README.md
```

---

## 致谢

- [PlayEdu](https://github.com/PlayEdu/PlayEdu) - 开源企业内部培训解决方案
- [MinIO](https://min.io/) - 高性能对象存储

## License

[AGPL-3.0](LICENSE) - 与上游 PlayEdu 保持一致
