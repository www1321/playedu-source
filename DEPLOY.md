# PlayEdu 非 Docker 部署指南 (Rocky Linux 10)

## 快速开始

```bash
# 1. 进入源码目录
cd playedu

# 2. 执行一键部署脚本（需要 root 权限）
sudo bash deploy/install.sh

# 3. 启动后端服务
sudo bash deploy/playedu.sh start

# 4. 查看日志确认启动成功
sudo bash deploy/playedu.sh log
```

## 访问地址

| 服务 | 地址 | 说明 |
|------|------|------|
| 管理后台 | http://YOUR_IP:9900 | 管理员登录 |
| PC 学员端 | http://YOUR_IP:9800 | 学员前台 |
| H5 移动端 | http://YOUR_IP:9801 | 移动端前台 |

默认管理员: `admin@playedu.xyz` / `playedu`（请登录后立即修改密码）

## 服务管理命令

```bash
# 启动 / 停止 / 重启
sudo bash deploy/playedu.sh start
sudo bash deploy/playedu.sh stop
sudo bash deploy/playedu.sh restart

# 查看状态 / 日志
sudo bash deploy/playedu.sh status
sudo bash deploy/playedu.sh log

# 重新构建后端 / 前端
sudo bash deploy/playedu.sh build
sudo bash deploy/playedu.sh build-fe
```

## 也可注册为 systemd 服务（可选）

```bash
sudo cp deploy/systemd/playedu.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable playedu
sudo systemctl start playedu

# 之后使用 systemctl 管理
sudo systemctl status playedu
sudo systemctl restart playedu
journalctl -u playedu -f
```

## 配置文件说明

| 文件 | 说明 |
|------|------|
| `playedu-api/playedu-api/src/main/resources/application-dev.yml` | 后端数据库连接配置 |
| `playedu-admin/.env` | 管理后台 API 地址配置 |
| `playedu-pc/.env` | PC 端 API 地址配置 |
| `playedu-h5/.env` | H5 端 API 地址配置 |
| `deploy/nginx/playedu.conf` | Nginx 反向代理配置 |
| `deploy/mysql/playedu.cnf` | MySQL 字符集配置 |

## 修改数据库密码

编辑 `playedu-api/playedu-api/src/main/resources/application-dev.yml`：

```yaml
spring:
  datasource:
    url: "jdbc:mysql://127.0.0.1:3306/playedu?useUnicode=true&characterEncoding=UTF-8&autoReconnect=true&useSSL=false&allowPublicKeyRetrieval=true"
    username: "root"
    password: "你的新密码"
```

修改后需重新构建并重启：

```bash
sudo bash deploy/playedu.sh build
sudo bash deploy/playedu.sh restart
```

## 防火墙放行端口

```bash
sudo firewall-cmd --permanent --add-port=9800/tcp
sudo firewall-cmd --permanent --add-port=9801/tcp
sudo firewall-cmd --permanent --add-port=9900/tcp
sudo firewall-cmd --reload
```
