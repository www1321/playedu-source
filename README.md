# PlayEdu 源码一键部署版

> 基于 [PlayEdu](https://github.com/PlayEdu/PlayEdu) 开源项目的非 Docker 源码部署方案，针对 Rocky Linux 10 深度适配，集成 MinIO 本地对象存储，一键完成全部环境搭建与应用部署。

PlayEdu 是一款开源的企业内部培训解决方案，本仓库在其源码基础上提供了完整的非容器化部署工具链，包括自动化的环境安装、编译构建、服务配置和存储集成。

---

## 目录

- [系统架构](#系统架构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [部署后操作](#部署后操作)
- [服务管理](#服务管理)
- [配置文件说明](#配置文件说明)
- [存储服务](#存储服务)
- [常见问题排查](#常见问题排查)
- [卸载](#卸载)
- [致谢](#致谢)

---

## 系统架构

### 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                      Nginx 反向代理                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ :9900    │  │ :9800    │  │ :9801    │              │
│  │ Admin后台 │  │ PC学员端  │  │ H5移动端  │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       └──────────────┼──────────────┘                    │
│                      │ /api/                             │
│              ┌───────▼────────┐                          │
│              │  :9898 后端API  │                          │
│              │  Spring Boot   │                          │
│              └───────┬────────┘                          │
└──────────────────────┼───────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   ┌────────────┐ ┌──────────┐ ┌──────────┐
   │  MariaDB   │ │  MinIO   │ │  文件系统  │
   │  :3306     │ │  :9000   │ │          │
   │  数据持久化  │ │  对象存储  │ │  前端静态  │
   └────────────┘ │  :9001   │ │          │
                  │  管理界面  │ └──────────┘
                  └──────────┘
```

### 后端技术栈

| 组件 | 技术 | 版本 | 说明 |
|------|------|------|------|
| 运行时 | Java (OpenJDK) | 17 | 推荐 17，兼容 21 |
| 框架 | Spring Boot | 3.3.4 | 后端主框架 |
| ORM | MyBatis Plus | 3.5.7 | 数据库操作 |
| 认证 | Sa-Token + JWT | 1.39.0 | 权限校验与令牌管理 |
| 对象存储 | AWS S3 SDK | 1.12.572 | 文件上传（兼容 MinIO） |
| 数据库驱动 | MySQL Connector/J | - | 兼容 MariaDB |
| 构建工具 | Maven | 3.9+ | 多模块项目管理 |

后端采用 Maven 多模块结构：

```
playedu-api/          ← 根 POM，多模块聚合
├── playedu-api/      ← API 入口（Controller、拦截器、启动类）
├── playedu-common/   ← 公共模块（工具类、配置、领域模型）
├── playedu-system/   ← 系统模块（管理员、部门、权限、配置、数据迁移）
├── playedu-course/   ← 课程模块（课程、章节、课时、学习记录）
└── playedu-resource/ ← 资源模块（资源分类、附件管理）
```

### 前端技术栈

| 组件 | 技术 | 版本 | 说明 |
|------|------|------|------|
| 框架 | React | 18 | UI 框架 |
| 构建 | Vite | 4.x | 开发服务器与打包 |
| UI 库 | Ant Design | 5.x | 管理后台组件库 |
| 状态管理 | Redux Toolkit | 1.9+ | 全局状态 |
| 语言 | TypeScript | 4.9+ | 类型安全 |
| 包管理 | pnpm | - | 依赖安装 |
| 样式 | Less | 4.x | CSS 预处理 |

前端包含三个独立项目：

```
playedu-admin/    ← 管理后台（Ant Design，端口 9900）
playedu-pc/       ← PC 学员端（端口 9800）
playedu-h5/       ← H5 移动端（端口 9801）
```

### 数据库

PlayEdu **无需手动导入 SQL**。后端首次启动时，`MigrationCheck` 组件会自动检测并创建所有数据表及初始配置数据（包括管理员账号、系统参数、S3 存储配置项等）。

---

## 与 Docker 版的差异

| 对比项 | Docker 版（官方） | 源码一键部署版（本仓库） |
|--------|-------------------|------------------------|
| **部署方式** | `docker compose up -d` 一条命令 | `bash deploy/install.sh` 一条命令 |
| **运行环境** | 全部容器化，依赖 Docker Engine | 直接运行在宿主机，无容器依赖 |
| **数据库** | Docker 内 MySQL 8 容器 | 宿主机 MariaDB（Rocky Linux 10 自带） |
| **前端部署** | 内置在 Java 容器中，由后端直接 serve | Nginx 独立提供静态文件服务 |
| **Nginx** | 无（前端由 Java 容器 serve） | 宿主机 Nginx 反向代理 + 静态服务 |
| **对象存储** | 需自行配置外部 S3 | 内置 MinIO，一键自动部署 |
| **API 端口** | 默认对外 9700 | 直接 9898（Nginx 代理后前端无感） |
| **配置方式** | `.env` 环境变量 + `compose.yml` | `application-dev.yml` + `.env` + Nginx conf |
| **字符集兼容** | MySQL 8 原生支持 `utf8mb4_0900_ai_ci` | 已修改为 `utf8mb4_unicode_ci`（MariaDB 兼容） |
| **资源占用** | Docker 引擎额外开销 | 无额外开销，更轻量 |
| **调试便利** | 需进入容器查看日志 | 直接访问日志文件，原生调试体验 |
| **适用场景** | 快速体验、标准化部署 | 生产环境、定制开发、深度运维 |

### 关键代码修改

为适配 Rocky Linux 10 + MariaDB 环境，本仓库对上游源码做了以下修改：

1. **`playedu-system/.../MigrationCheck.java`**：将 LDAP 相关表的 `COLLATE utf8mb4_0900_ai_ci` 替换为 `COLLATE utf8mb4_unicode_ci`（MariaDB 不支持 MySQL 8.0 的 0900 排序规则）

---

## 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Rocky Linux 10 / RHEL 10 / CentOS Stream 10（x86_64） |
| 内存 | ≥ 4GB（推荐 8GB） |
| 磁盘 | ≥ 20GB（不含课程视频存储） |
| 网络 | 需要访问外网（安装依赖和下载 MinIO） |
| 权限 | root 或 sudo 权限 |

> **其他 Linux 发行版**：Ubuntu 22.04/24.04、Debian 12 等也可使用，但需手动调整包管理命令（`dnf` → `apt`）和部分路径。核心流程不变。

---

## 快速开始

### 1. 获取源码

```bash
git clone https://github.com/你的用户名/PlayEdu.git
cd PlayEdu
```

### 2. 执行一键部署

```bash
sudo bash deploy/install.sh
```

脚本会自动完成以下 9 个步骤：

| 步骤 | 内容 |
|------|------|
| 1/9 | 安装基础依赖（JDK 17、Maven、Node.js、pnpm、Nginx、MariaDB） |
| 2/9 | 配置 MariaDB 数据库（创建库、设置字符集、配置密码） |
| 3/9 | 部署 MinIO 对象存储（下载、注册服务、创建 Bucket） |
| 4/9 | 复制源码到 `/opt/playedu` |
| 5/9 | Maven 编译后端（`mvn clean package`） |
| 6/9 | pnpm 编译三个前端项目 |
| 7/9 | 部署前端静态文件到 `/opt/playedu/frontend/` |
| 8/9 | 配置 Nginx 反向代理（含 SELinux 端口放行） |
| 9/9 | 首次启动后端 → 自动建表 → 写入 S3 存储配置 |

部署过程中会交互式询问以下配置（均可直接回车使用默认值）：

```
请确认以下配置（直接回车使用默认值）:

  MinIO 数据存储目录 [/opt/minio/data]:
  MinIO API 端口 [9000]:
  MinIO 管理界面端口 [9001]:
  MinIO 管理账号 [playedu]:
  MinIO 管理密码 [playedu123]:
  MySQL 数据库密码 [playeduxyz]:
```

### 3. 启动服务

```bash
sudo bash /opt/playedu/deploy/playedu.sh start
```

### 4. 访问系统

| 服务 | 地址 | 默认账号 |
|------|------|----------|
| 管理后台 | `http://YOUR_IP:9900` | `admin@playedu.xyz` / `playedu` |
| PC 学员端 | `http://YOUR_IP:9800` | 前台注册 |
| H5 移动端 | `http://YOUR_IP:9801` | 前台注册 |
| MinIO 管理界面 | `http://YOUR_IP:9001` | 部署时设置 |

> ⚠️ **请登录后立即修改默认密码！**

### 5. 防火墙放行（如需外网访问）

```bash
sudo firewall-cmd --permanent --add-port={9800,9801,9900}/tcp
sudo firewall-cmd --reload
```

---

## 部署后操作

### 注册为 systemd 服务（可选）

如果希望 PlayEdu 后端随系统自动启动，可以注册为 systemd 服务：

```bash
sudo cp /opt/playedu/deploy/systemd/playedu.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable playedu
sudo systemctl start playedu
```

注册后使用 systemctl 管理：

```bash
sudo systemctl status playedu    # 查看状态
sudo systemctl restart playedu   # 重启
journalctl -u playedu -f         # 查看日志
```

### 挂载独立磁盘用于 MinIO 存储（推荐）

如果课程资源较多，建议将 MinIO 数据目录挂载到独立磁盘：

```bash
# 1. 格式化磁盘（以 /dev/sdb 为例）
sudo mkfs.xfs /dev/sdb

# 2. 创建挂载点
sudo mkdir -p /data/minio

# 3. 挂载
sudo mount /dev/sdb /data/minio

# 4. 写入 fstab 实现开机自动挂载
echo '/dev/sdb /data/minio xfs defaults 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload

# 5. 迁移已有数据（如果之前已部署）
sudo systemctl stop minio
sudo cp -a /opt/minio/data/* /data/minio/
sudo rm -rf /opt/minio/data/*

# 6. 修改 MinIO 服务配置中的数据目录
sudo vi /etc/systemd/system/minio.service
# 将 ExecStart 中的数据目录改为 /data/minio
sudo systemctl daemon-reload
sudo systemctl start minio
```

---

## 服务管理

部署完成后，使用 `playedu.sh` 脚本管理服务：

```bash
sudo bash /opt/playedu/deploy/playedu.sh <命令>
```

| 命令 | 说明 |
|------|------|
| `start` | 启动后端（自动启动 MinIO） |
| `stop` | 停止后端 |
| `restart` | 重启后端 |
| `status` | 查看所有服务状态 + 端口监听 |
| `log` | 实时查看后端日志（`tail -f`） |
| `build` | 重新编译后端 JAR |
| `build-fe` | 重新编译前端并部署到 Nginx |

### 查看服务状态

```bash
$ sudo bash /opt/playedu/deploy/playedu.sh status

--- 服务状态 ---
  PlayEdu 后端:  运行中 (PID: 12345)
  MinIO 存储:    运行中
  MySQL/MariaDB: 运行中
  Nginx:         运行中

--- 端口监听 ---
  LISTEN  0  128  0.0.0.0:9898  *:*   (PlayEdu API)
  LISTEN  0  128  0.0.0.0:9800  *:*   (PC 学员端)
  LISTEN  0  128  0.0.0.0:9801  *:*   (H5 移动端)
  LISTEN  0  128  0.0.0.0:9900  *:*   (管理后台)
  LISTEN  0  128  0.0.0.0:9000  *:*   (MinIO API)
  LISTEN  0  128  0.0.0.0:9001  *:*   (MinIO Console)
  LISTEN  0  80  0.0.0.0:3306   *:*   (MariaDB)
```

---

## 配置文件说明

### 后端配置

#### `playedu-api/playedu-api/src/main/resources/application.yml`

主配置文件（一般不需要修改），包含：

```yaml
server:
  port: 9898                          # 后端 API 端口

spring:
  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      minimum-idle: 1                 # 最小数据库连接数
      maximum-pool-size: 10           # 最大数据库连接数

sa-token:
  token-name: "Authorization"         # Token 请求头名称
  timeout: 1296000                    # Token 有效期（秒），默认 15 天
  is-concurrent: false                # 是否允许同账号并发登录
  jwt-secret-key: "playeduxyz"        # JWT 签名密钥（生产环境请修改！）
  token-prefix: "Bearer"              # Token 前缀

playedu:
  limiter:
    duration: 60                      # 接口限流时间窗口（秒）
    limit: 360                        # 时间窗口内最大请求数
```

#### `playedu-api/playedu-api/src/main/resources/application-dev.yml`

开发/部署环境配置（**部署前需确认**），包含数据库连接：

```yaml
spring:
  datasource:
    url: "jdbc:mysql://127.0.0.1:3306/playedu?useUnicode=true&characterEncoding=UTF-8&autoReconnect=true&useSSL=false&allowPublicKeyRetrieval=true"
    username: "root"
    password: "playeduxyz"            # 与部署时设置的密码一致
```

> 此文件在官方仓库中被 `.gitignore` 忽略，本仓库已预置默认值。如需修改数据库密码，需同步修改此文件并重新构建。

### 前端配置

#### `playedu-admin/.env` / `playedu-pc/.env` / `playedu-h5/.env`

三个前端项目的 API 地址配置：

```
VITE_APP_URL=/api/
```

此配置使前端通过 Nginx 反向代理 `/api/` 路径访问后端，无需硬编码后端地址。**一般不需要修改。**

### 部署配置

#### `deploy/nginx/playedu.conf`

Nginx 反向代理配置，包含三个 server 块：

| 端口 | 服务 | 静态文件目录 |
|------|------|-------------|
| 9800 | PC 学员端 | `/opt/playedu/frontend/pc` |
| 9801 | H5 移动端 | `/opt/playedu/frontend/h5` |
| 9900 | 管理后台 | `/opt/playedu/frontend/admin` |

每个 server 块的核心逻辑：

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:9898/;   # 反向代理到后端
}

location ~* ^/(?![api].*) {
    try_files $uri /index.html;           # SPA 路由回退
}
```

上传文件大小限制为 `client_max_body_size 500m;`。

#### `deploy/mysql/playedu.cnf`

MariaDB/MySQL 字符集配置：

```ini
[mysqld]
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
default-authentication-plugin=mysql_native_password
```

#### `deploy/systemd/playedu.service`

可选的 systemd 服务单元文件，用于将 PlayEdu 后端注册为系统服务，实现开机自启和崩溃自动重启。

---

## 存储服务

PlayEdu 使用 S3 协议进行文件存储（视频、图片、课件等），不支持本地文件系统存储。本方案集成了 [MinIO](https://min.io/) 作为 S3 兼容的本地对象存储服务。

### 存储架构

```
上传请求 → PlayEdu 后端 → S3 SDK → MinIO (localhost:9000)
                                    │
                                    └── /opt/minio/data/playedu/ (磁盘)
```

### S3 配置项

部署脚本会自动将以下配置写入数据库 `app_config` 表：

| 配置键 | 值 | 说明 |
|--------|-----|------|
| `s3.access_key` | 部署时设置 | MinIO 管理账号 |
| `s3.secret_key` | 部署时设置 | MinIO 管理密码 |
| `s3.bucket` | `playedu` | 存储桶名称 |
| `s3.region` | `us-east-1` | 区域（MinIO 固定值，不可为空） |
| `s3.endpoint` | `http://IP:9000` | MinIO API 地址 |

### 手动修改存储配置

如需修改存储配置，可直接操作数据库：

```sql
-- 查看当前配置
SELECT * FROM playedu.app_config WHERE key_name LIKE 's3.%';

-- 修改 endpoint（如更换 IP）
UPDATE playedu.app_config SET key_value='http://新IP:9000' WHERE key_name='s3.endpoint';
```

修改后需重启后端服务生效。

### MinIO 管理界面

访问 `http://YOUR_IP:9001`，使用部署时设置的账号密码登录，可以：

- 浏览和管理文件
- 创建/删除存储桶
- 查看存储用量
- 配置访问策略

---

## 常见问题排查

### 后端无法启动

**查看日志：**

```bash
# 使用管理脚本
sudo bash /opt/playedu/deploy/playedu.sh log

# 或直接查看日志文件
sudo tail -100 /var/log/playedu.log

# 如果使用 systemd
sudo journalctl -u playedu -n 100 --no-pager
```

**常见原因：**

| 错误信息 | 原因 | 解决方法 |
|----------|------|----------|
| `Communications link failure` / `Connection refused` | 数据库未启动 | `sudo systemctl start mariadb` |
| `Unknown database 'playedu'` | 数据库未创建 | `mysql -u root -p -e "CREATE DATABASE playedu DEFAULT CHARACTER SET utf8mb4;"` |
| `Access denied for user 'root'@'localhost'` | 数据库密码不匹配 | 检查 `application-dev.yml` 中的密码是否与数据库一致 |
| `Port 9898 already in use` | 端口被占用 | `ss -tlnp \| grep 9898` 查看占用进程并终止 |
| `Unknown collation 'utf8mb4_0900_ai_ci'` | MariaDB 不兼容 | 确认使用本仓库修改过的 `MigrationCheck.java` |

### 前端页面空白或 502

**排查步骤：**

```bash
# 1. 检查 Nginx 是否运行
sudo systemctl status nginx

# 2. 检查 Nginx 配置是否正确
sudo nginx -t

# 3. 检查后端是否正常运行
curl http://127.0.0.1:9898/api/v1/system/config

# 4. 检查前端静态文件是否存在
ls /opt/playedu/frontend/admin/
ls /opt/playedu/frontend/pc/
ls /opt/playedu/frontend/h5/
```

### Nginx 启动失败（端口绑定错误）

```
bind() to 0.0.0.0:9800 failed (13: Permission denied)
```

这是 SELinux 阻止了非标准 HTTP 端口。解决方法：

```bash
# 检查 SELinux 状态
getenforce

# 如果是 Enforcing，放行端口
sudo semanage port -a -t http_port_t -p tcp 9800
sudo semanage port -a -t http_port_t -p tcp 9801
sudo semanage port -a -t http_port_t -p tcp 9900

# 重启 Nginx
sudo systemctl restart nginx
```

> 部署脚本已自动处理此问题。如果手动修改了端口，需要额外执行上述命令。

### 上传文件报"存储服务未配置"

**原因：** 数据库中 S3 配置项不完整，特别是 `s3.region` 为空。

**排查：**

```sql
SELECT key_name, key_value FROM playedu.app_config WHERE key_name LIKE 's3.%';
```

确保所有 5 个字段都有值，`s3.region` 不能为空（MinIO 使用 `us-east-1`）。

**修复：**

```sql
UPDATE playedu.app_config SET key_value='us-east-1' WHERE key_name='s3.region';
```

### MinIO 无法访问

```bash
# 检查 MinIO 服务状态
sudo systemctl status minio

# 查看日志
sudo journalctl -u minio -n 50 --no-pager

# 检查端口
ss -tlnp | grep -E '9000|9001'

# 测试连通性
curl http://127.0.0.1:9000/minio/health/live

# 检查数据目录权限
ls -la /opt/minio/data/
```

### MinIO 数据目录磁盘空间不足

```bash
# 查看磁盘使用
df -h /opt/minio/data

# 查看目录大小
du -sh /opt/minio/data/*
```

如需迁移到更大磁盘，参见 [挂载独立磁盘用于 MinIO 存储](#挂载独立磁盘用于-minio-存储推荐)。

### 数据库连接数不足

如果并发用户较多，可能遇到连接池耗尽：

```
HikariPool-1 - Connection is not available, request timed out
```

修改 `application.yml` 中的连接池配置：

```yaml
spring:
  datasource:
    hikari:
      minimum-idle: 5
      maximum-pool-size: 30
      connection-timeout: 30000
```

修改后需重新构建并重启。

### JDK 安装失败

Rocky Linux 10 的 JDK 17 位于 CRB 仓库中，如果 `dnf install` 失败：

```bash
# 手动启用 CRB 仓库
sudo dnf config-manager --set-enabled crb

# 再次安装
sudo dnf install -y java-17-openjdk java-17-openjdk-devel

# 验证
java -version
```

部署脚本已内置三级回退机制：CRB 仓库 → JDK 21 → 手动下载安装。

### MariaDB vs MySQL 服务名冲突

Rocky Linux 10 中 `mysql-server` 实际安装的是 MariaDB，`mysqld.service` 是指向 `mariadb.service` 的符号链接。直接操作 `mysqld` 可能报错：

```
Failed to enable unit: Refusing to operate on linked unit file
```

**解决：** 始终使用 `mariadb` 作为服务名：

```bash
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl status mariadb
```

---

## 卸载

```bash
sudo bash /opt/playedu/deploy/uninstall.sh
```

卸载脚本会清理以下内容（需输入 `yes` 确认）：

- 停止所有相关服务
- 删除 systemd 服务文件
- 删除 Nginx 配置
- 删除 `/opt/playedu` 和 `/opt/minio` 目录
- 删除 `playedu` 数据库
- 删除 MySQL 字符集配置

> ⚠️ **此操作不可逆，所有数据将被永久删除！**

---

## 目录结构

```
PlayEdu/
├── deploy/                          # 部署工具
│   ├── install.sh                   # 一键部署脚本
│   ├── playedu.sh                   # 服务管理脚本
│   ├── uninstall.sh                 # 卸载清理脚本
│   ├── nginx/
│   │   └── playedu.conf             # Nginx 反向代理配置
│   ├── mysql/
│   │   └── playedu.cnf              # MySQL 字符集配置
│   └── systemd/
│       └── playedu.service          # systemd 服务单元文件
├── playedu-api/                     # 后端源码
│   ├── playedu-api/                 #   API 入口模块
│   ├── playedu-common/              #   公共模块
│   ├── playedu-system/              #   系统模块
│   ├── playedu-course/              #   课程模块
│   └── playedu-resource/            #   资源模块
├── playedu-admin/                   # 管理后台前端
├── playedu-pc/                      # PC 学员端前端
├── playedu-h5/                      # H5 移动端前端
├── .env.example                     # 环境变量示例（参考）
├── LICENSE                          # AGPL-3.0 许可证
└── README.md                        # 本文档
```

部署后的运行时目录：

```
/opt/playedu/                       # 应用主目录
├── playedu-api/                     # 后端（含编译后的 JAR）
├── frontend/
│   ├── admin/                       # 管理后台静态文件
│   ├── pc/                          # PC 端静态文件
│   └── h5/                          # H5 端静态文件
└── deploy/                          # 部署脚本

/opt/minio/data/                     # MinIO 对象存储数据
/var/log/playedu.log                 # 后端运行日志
/var/run/playedu.pid                 # 后端 PID 文件
```

---

## 端口汇总

| 端口 | 服务 | 说明 |
|------|------|------|
| 9898 | PlayEdu API | 后端接口 |
| 9800 | Nginx | PC 学员端 |
| 9801 | Nginx | H5 移动端 |
| 9900 | Nginx | 管理后台 |
| 9000 | MinIO | S3 API |
| 9001 | MinIO Console | 管理界面 |
| 3306 | MariaDB | 数据库 |

---

## 致谢

- [PlayEdu](https://github.com/PlayEdu/PlayEdu) - 开源企业内部培训解决方案
- [MinIO](https://min.io/) - 高性能对象存储
- [Spring Boot](https://spring.io/projects/spring-boot) - Java 后端框架
- [React](https://react.dev/) - 前端 UI 框架
- [Ant Design](https://ant.design/) - UI 组件库

---

## License

[AGPL-3.0](LICENSE) - 与上游 PlayEdu 保持一致
