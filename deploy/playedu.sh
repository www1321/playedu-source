#!/bin/bash
# ============================================================
# PlayEdu 服务管理脚本
# 用法: sudo bash deploy/playedu.sh {start|stop|restart|status|log|build|build-fe}
# ============================================================

INSTALL_DIR="/opt/playedu"
JAR_FILE="${INSTALL_DIR}/playedu-api/playedu-api/target/playedu-api.jar"
PID_FILE="/var/run/playedu.pid"
LOG_FILE="/var/log/playedu.log"
JAVA_OPTS="-Xms512m -Xmx1024m"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE"
    fi
}

is_running() {
    local pid=$(get_pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

start() {
    if is_running; then
        echo -e "${YELLOW}PlayEdu 后端已在运行中 (PID: $(get_pid))${NC}"
        return 1
    fi

    if [ ! -f "$JAR_FILE" ]; then
        echo -e "${RED}错误: 找不到 JAR 文件 ${JAR_FILE}${NC}"
        echo -e "${RED}请先运行: cd ${INSTALL_DIR}/playedu-api && ./mvnw clean package -Dmaven.test.skip=true${NC}"
        return 1
    fi

    # 确保 MinIO 已启动
    if systemctl list-unit-files minio.service &>/dev/null; then
        systemctl start minio 2>/dev/null || true
    fi

    echo -e "${GREEN}正在启动 PlayEdu 后端...${NC}"
    nohup java ${JAVA_OPTS} -jar "$JAR_FILE" \
        --spring.profiles.active=dev \
        > "$LOG_FILE" 2>&1 &

    echo $! > "$PID_FILE"

    # 等待启动
    for i in $(seq 1 30); do
        if is_running; then
            if curl -s http://127.0.0.1:9898/api/v1/system/config > /dev/null 2>&1; then
                echo -e "${GREEN}PlayEdu 后端启动成功! (PID: $(get_pid))${NC}"
                return 0
            fi
        fi
        sleep 2
    done

    echo -e "${YELLOW}PlayEdu 后端进程已启动 (PID: $(get_pid))，正在初始化数据库...${NC}"
    echo -e "${YELLOW}请查看日志确认启动状态: $0 log${NC}"
}

stop() {
    if ! is_running; then
        echo -e "${YELLOW}PlayEdu 后端未在运行${NC}"
        rm -f "$PID_FILE"
        return 0
    fi

    local pid=$(get_pid)
    echo -e "${GREEN}正在停止 PlayEdu 后端 (PID: ${pid})...${NC}"
    kill "$pid"

    for i in $(seq 1 15); do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$PID_FILE"
            echo -e "${GREEN}PlayEdu 后端已停止${NC}"
            return 0
        fi
        sleep 1
    done

    kill -9 "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    echo -e "${GREEN}PlayEdu 后端已强制停止${NC}"
}

restart() {
    stop
    sleep 2
    start
}

status() {
    echo -e "${YELLOW}--- 服务状态 ---${NC}"

    # PlayEdu 后端
    if is_running; then
        echo -e "  PlayEdu 后端:  ${GREEN}运行中${NC} (PID: $(get_pid))"
    else
        echo -e "  PlayEdu 后端:  ${RED}未运行${NC}"
    fi

    # MinIO
    if systemctl is-active minio &>/dev/null; then
        echo -e "  MinIO 存储:    ${GREEN}运行中${NC}"
    else
        echo -e "  MinIO 存储:    ${RED}未运行${NC}"
    fi

    # MariaDB/MySQL
    if systemctl is-active mariadb &>/dev/null || systemctl is-active mysqld &>/dev/null; then
        echo -e "  MySQL/MariaDB: ${GREEN}运行中${NC}"
    else
        echo -e "  MySQL/MariaDB: ${RED}未运行${NC}"
    fi

    # Nginx
    if systemctl is-active nginx &>/dev/null; then
        echo -e "  Nginx:        ${GREEN}运行中${NC}"
    else
        echo -e "  Nginx:        ${RED}未运行${NC}"
    fi

    # 端口监听
    echo ""
    echo -e "${YELLOW}--- 端口监听 ---${NC}"
    ss -tlnp 2>/dev/null | grep -E '9898|9800|9801|9900|9000|9001|3306' | while read line; do
        echo "  $line"
    done
}

log() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo -e "${RED}日志文件不存在: ${LOG_FILE}${NC}"
    fi
}

build_backend() {
    echo -e "${GREEN}正在构建后端...${NC}"
    cd "${INSTALL_DIR}/playedu-api"
    ./mvnw clean package -Dmaven.test.skip=true
    echo -e "${GREEN}后端构建完成!${NC}"
    echo -e "${YELLOW}新 JAR 文件: ${JAR_FILE}${NC}"
    echo -e "${YELLOW}请运行 $0 restart 以应用更新${NC}"
}

build_frontend() {
    echo -e "${GREEN}正在构建前端...${NC}"

    echo "  构建 playedu-admin..."
    cd "${INSTALL_DIR}/playedu-admin"
    pnpm install && pnpm build
    cp -r dist/* "${INSTALL_DIR}/frontend/admin/"

    echo "  构建 playedu-pc..."
    cd "${INSTALL_DIR}/playedu-pc"
    pnpm install && pnpm build
    cp -r dist/* "${INSTALL_DIR}/frontend/pc/"

    echo "  构建 playedu-h5..."
    cd "${INSTALL_DIR}/playedu-h5"
    pnpm install && pnpm build
    cp -r dist/* "${INSTALL_DIR}/frontend/h5/"

    echo -e "${GREEN}前端构建并部署完成!${NC}"
    systemctl reload nginx
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    log)
        log
        ;;
    build)
        build_backend
        ;;
    build-fe)
        build_frontend
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|log|build|build-fe}"
        echo ""
        echo "  start     - 启动后端服务（自动启动 MinIO）"
        echo "  stop      - 停止后端服务"
        echo "  restart   - 重启后端服务"
        echo "  status    - 查看所有服务运行状态"
        echo "  log       - 查看后端实时日志"
        echo "  build     - 重新构建后端"
        echo "  build-fe  - 重新构建并部署前端"
        exit 1
        ;;
esac
