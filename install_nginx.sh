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
    --with-threads \
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
worker_cpu_affinity auto;  # 自动绑定工作进程到不同CPU核心，减少上下文切换（Nginx1.9.10+支持）
worker_rlimit_nofile 100000; # 突破系统文件描述符限制（需配合 `ulimit -n 100000`）
error_log logs/error.log warn;
pid run/nginx.pid;

events {
    use epoll; # 启用epoll事件模型（Linux最优，支持百万级并发）
    worker_connections 65535; # 每个工作进程最大并发连接数（默认1024）
    multi_accept on; # 工作进程一次接受所有新连接，减少accept()调用开销
    accept_mutex on; # 启用连接互斥锁，避免惊群效应（Nginx 1.11.3+默认on）
    accept_mutex_delay 500ms; # 互斥锁等待时间
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
    keepalive_timeout 65; # 长连接超时时间（默认75秒，建议60-120秒）
    keepalive_requests 10000; # 一个长连接最多处理的请求数（默认100，高并发场景调大）
    keepalive_disable msie6; # 禁用IE6长连接（兼容性问题）
    types_hash_max_size 2048;

    client_header_timeout 15; # 读取请求头超时（默认60秒）
    client_body_timeout 15; # 读取请求体超时（默认60秒）
    send_timeout 15; # 发送响应超时（默认60秒，仅在两次写操作之间生效）
    lingering_timeout 5; # 连接关闭后，等待残留数据的时间（默认30秒）
    client_max_body_size 10m;

    # 对静态文件设置强缓存（推荐CDN/静态资源服务器配置）
    expires 7d; # 缓存7天（图片、JS、CSS等不变资源）
    add_header Cache-Control "public, max-age=604800"; # 配合expires，兼容HTTP/1.1
    add_header ETag ""; # 禁用ETag（减少服务器校验开销，依赖Last-Modified即可）
    add_header Last-Modified $date_gmt; # 静态文件最后修改时间
    
    # Gzip压缩
    gzip on;
    gzip_vary on; # 响应头添加Vary: Accept-Encoding，支持CDN缓存不同压缩版本
    gzip_proxied any; # 对反向代理的响应也压缩
    gzip_comp_level 6; # 压缩级别（1-9，级别越高压缩率越高但CPU开销越大，推荐6）
    gzip_types text/plain text/css application/json application/javascript
    text/xml application/xml application/xml+rss image/svg+xml; # 需压缩的文件类型
    gzip_min_length 1k; # 小于1KB的文件不压缩（避免压缩开销大于收益）
    gzip_buffers 16 8k; # 压缩缓冲区大小
    # Brotli压缩（比Gzip压缩率更高，需Nginx编译时启用ngx_brotli模块）
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css application/json application/javascript
    text/xml application/xml;

    # 资源加载优化
    # 开启TCP快速打开（TFO，减少TCP握手延迟，需内核支持 `net.ipv4.tcp_fastopen = 3`）
    tcp_nopush on; # 启用TCP_CORK选项，合并小数据包发送（提升吞吐量）
    tcp_nodelay on; # 禁用Nagle算法，小数据包立即发送（降低延迟，适合实时通信）
    sendfile on; # 启用零拷贝（sendfile()系统调用，避免内核态与用户态数据拷贝，提升静态文
    件传输性能）

    #反向代理优化
    # 后端服务连接池（复用连接，减少握手开销）
    proxy_connect_timeout 10; # 与后端建立连接超时（默认60秒）
    proxy_send_timeout 15; # 向后端发送请求超时
    proxy_read_timeout 15; # 读取后端响应超时（需与后端超时保持一致，避免超时不一致导致问
    题）
    proxy_buffering on; # 启用代理缓冲区（减少后端响应延迟对客户端的影响）
    proxy_buffer_size 4k; # 缓冲区初始大小（默认4k/8k）
    proxy_buffers 4 16k; # 缓冲区数量和每个大小
    proxy_busy_buffers_size 32k; # 忙缓冲区最大大小（需大于 proxy_buffers 单个大小）
    proxy_cache_path /var/nginx/proxy_cache levels=1:2 keys_zone=proxy_cache:100m
    inactive=7d max_size=10g; # 代理缓存（缓存后端响应，减轻后端压力）

    # 具体location中启用缓存
    location /api/ {
    proxy_pass http://backend_server;
    proxy_cache proxy_cache;
    proxy_cache_key "$scheme$request_method$host$request_uri"; # 缓存key（避免缓存
    穿透）
    proxy_cache_valid 200 304 7d; # 200/304响应缓存7天
    proxy_cache_valid any 1m; # 其他响应缓存1分钟
    proxy_cache_use_stale error timeout invalid_header updating http_500 http_502
    http_503 http_504; # 后端异常时使用过期缓存（提升可用性）

    # https场景优化
    server {
    listen 443 ssl http2; # 启用HTTP/2（多路复用，提升并发请求性能，需SSL支持）
    ssl_protocols TLSv1.2 TLSv1.3; # 禁用不安全协议（TLSv1.0/TLSv1.1）
    ssl_prefer_server_ciphers on; # 优先使用服务器加密套件
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCMSHA256:
    ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384; # 推荐加密套件
    （前向安全+高性能）
    ssl_session_cache shared:SSL:10m; # SSL会话缓存（10MB，约40000个会话）
    ssl_session_timeout 1d; # 会话超时时间（1天，减少SSL握手开销）
    ssl_session_tickets on; # 启用会话票据（TLSv1.3默认支持，加速重连）
    ssl_stapling on; # 启用OCSP装订（减少客户端验证证书的网络请求）
    ssl_stapling_verify on; # 验证OCSP响应
    resolver 8.8.8.8 1.1.1.1 valid=300s; # OCSP解析器（DNS）
    }

    # 静态资源优化
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2|woff|ttf)$ {
    root /data/static; # 静态资源根目录
    expires 30d; # 长缓存（30天）
    add_header Cache-Control "public, immutable"; # immutable 标记资源不修改，禁止浏
    览器重新验证
    access_log off; # 禁用静态资源访问日志（减少IO开销）
    log_not_found off; # 404不记录日志
    gzip on; # 启用压缩
    brotli on;
    }
    # 大文件下载优化（断点续传）
    location ~* \.(iso|zip|tar\.gz|mp4)$ {
    root /data/download;
    expires 7d;
    add_header Accept-Ranges bytes; # 支持断点续传
    sendfile on;
    tcp_nopush on; # 合并数据包，提升下载速度
    }
    #流量安全优化
    # 限流配置（按IP限制，10r/s=10请求/秒， burst=20=突发20个请求，nodelay=不等待）
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;
    # 连接数限制（单IP最大100个连接）
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
    server {
    location /api/ {
    limit_req zone=req_limit burst=20 nodelay;
    limit_conn conn_limit 100;
    proxy_pass http://backend_server;
        }
    }
    
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
