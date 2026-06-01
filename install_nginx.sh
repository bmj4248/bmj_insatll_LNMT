#!/bin/bash
# ============================================
# nginx 源码安装脚本 (Rocky/CentOS/RHEL)
# ============================================

# --- 可配置变量 ---
# nginx版本号，修改这里即可换版本
ver="1.22.1"

# 安装路径
prefix="/data/soft/nginx"

# 源码包路径（上传的tar.gz文件位置）
source_file="/root/nginx-${ver}.tar.gz"

# 编译用户
user="nginx"
group="nginx"

# 配置文件路径
conf_file="${prefix}/conf/nginx.conf"

# PID文件路径
pid_file="${prefix}/run/nginx.pid"

# systemd服务文件路径
service_file="/usr/lib/systemd/system/nginx.service"

# --- 1. 清理系统原有nginx ---
echo "=== 1. 停止并清理原有nginx ==="

# 停止进程
systemctl stop nginx 2>/dev/null
pkill -9 nginx 2>/dev/null
sleep 2

# 卸载系统包
dnf remove -y nginx nginx-all-modules nginx-filesystem nginx-mod-* 2>/dev/null
yum remove -y nginx nginx-all-modules nginx-filesystem nginx-mod-* 2>/dev/null

# 删除用户
groupdel ${group} 2>/dev/null
userdel -r ${user} 2>/dev/null

# 删除残留目录和文件
rm -rf /etc/nginx
rm -rf /usr/share/nginx
rm -rf /var/log/nginx
rm -rf /var/cache/nginx
rm -rf /var/lib/nginx
rm -rf /run/nginx
rm -rf /run/php-fpm
rm -rf /var/run/nginx
rm -rf /usr/local/nginx
rm -rf /tmp/nginx*
rm -f /usr/sbin/nginx
rm -f /usr/local/sbin/nginx
rm -f /usr/bin/nginx
rm -f /usr/local/bin/nginx

# 删除systemd服务
rm -f /etc/systemd/system/nginx.service
rm -f /usr/lib/systemd/system/nginx.service
rm -f /lib/systemd/system/nginx.service
systemctl daemon-reload 2>/dev/null

# 删除环境配置
rm -f /etc/sysconfig/nginx
rm -f /etc/default/nginx
rm -f /etc/profile.d/nginx.sh

# 删除man手册
rm -rf /usr/share/man/man8/nginx*
rm -rf /usr/share/man/man1/nginx*

# 如果之前安装过，删除旧目录
rm -rf ${prefix}

echo "清理完成"

# --- 2. 安装编译依赖 ---
echo "=== 2. 安装编译依赖 ==="
dnf install -y gcc make gcc-c++ glibc glibc-devel pcre2 pcre2-devel openssl openssl-devel systemd-devel zlib-devel libxml2 libxml2-devel libxslt libxslt-devel 2>/dev/null || yum install -y gcc make gcc-c++ glibc glibc-devel pcre2 pcre2-devel openssl openssl-devel systemd-devel zlib-devel libxml2 libxml2-devel libxslt libxslt-devel 2>/dev/null

# --- 3. 创建用户 ---
echo "=== 3. 创建运行用户 ==="
groupadd ${group}
useradd -r -g ${group} -s /usr/sbin/nologin ${user}

# --- 4. 解压源码 ---
echo "=== 4. 解压源码包 ==="
cd /usr/local/src
rm -rf nginx-${ver}
tar xf ${source_file}
cd nginx-${ver}

# --- 5. 编译配置 ---
echo "=== 5. 编译配置 ==="
./configure \
    --prefix=${prefix} \
    --user=${user} \
    --group=${group} \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_auth_request_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_degradation_module \
    --with-http_slice_module \
    --with-compat \
    --with-file-aio \
    --with-threads
    --add-module=/data/soft/redis2-nginx-module

# --- 6. 编译安装 ---
echo "=== 6. 编译安装 ==="
make -j$(nproc)
make install

# --- 7. 创建必要目录 ---
echo "=== 7. 创建目录结构 ==="
mkdir -p ${prefix}/conf/conf.d
mkdir -p ${prefix}/run
mkdir -p ${prefix}/logs
mkdir -p ${prefix}/temp/client_body_temp
mkdir -p ${prefix}/temp/proxy_temp
mkdir -p ${prefix}/temp/fastcgi_temp
mkdir -p ${prefix}/temp/uwsgi_temp
mkdir -p ${prefix}/temp/scgi_temp
mkdir -p ${prefix}/html

# --- 8. 修改权限 ---
echo "=== 8. 设置权限 ==="
chown -R ${user}:${group} ${prefix}
chown ${user}:${group} ${prefix}/run

# --- 9. 生成主配置文件 ---
echo "=== 9. 生成主配置文件 ==="
cat > ${conf_file} << 'EOFCONF'
user nginx nginx;
worker_processes auto;
error_log logs/error.log warn;
pid run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include mime.types;
    default_type application/octet-stream;

    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    # 访问日志
    access_log logs/access.log main;

    # 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # 包含虚拟主机配置
    include conf/conf.d/*.conf;
}
EOFCONF

# --- 10. 生成默认虚拟主机配置 ---
echo "=== 10. 生成默认虚拟主机 ==="
cat > ${prefix}/conf/conf.d/vhost.conf << 'EOFVHOST'
server {
    listen 80 default_server;
    server_name _;

    root html;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root html;
    }
}
EOFVHOST

# --- 11. 复制man手册 ---
echo "=== 11. 复制man手册 ==="
cp /usr/local/src/nginx-${ver}/man/nginx.8 /usr/share/man/man8/
gzip /usr/share/man/man8/nginx.8

# --- 12. 添加环境变量 ---
echo "=== 12. 添加环境变量 ==="
echo "export PATH=${prefix}/sbin:\$PATH" > /etc/profile.d/nginx.sh
source /etc/profile.d/nginx.sh

# --- 13. 生成systemd服务文件 ---
echo "=== 13. 生成systemd服务 ==="
cat > ${service_file} << EOFSERVICE
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=${pid_file}
ExecStartPre=${prefix}/sbin/nginx -t -c ${conf_file}
ExecStart=${prefix}/sbin/nginx -c ${conf_file}
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
ExecStartPost=/bin/sleep 0.1
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOFSERVICE

# --- 14. 重载systemd并启动 ---
echo "=== 14. 启动服务 ==="
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# --- 15. 验证 ---
echo ""
echo "=== 安装完成 ==="
echo "版本: ${ver}"
echo "路径: ${prefix}"
echo "配置: ${conf_file}"
echo "虚拟主机: ${prefix}/conf/conf.d/"
echo ""
${prefix}/sbin/nginx -V
echo ""
echo "状态:"
systemctl status nginx --no-pager
echo ""
echo "端口监听:"
ss -tlnp | grep :80 || netstat -tnlp | grep nginx
