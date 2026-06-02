#!/bin/bash
# ============================================
# nginx 源码安装脚本 (Rocky/CentOS/RHEL)
# ============================================

# --- 可配置变量 ---
ver="1.22.1"
prefix="/data/soft/nginx"
source_file="/root/nginx-${ver}.tar.gz"
user="nginx"
group="nginx"
conf_file="${prefix}/conf/nginx.conf"
pid_file="${prefix}/run/nginx.pid"
service_file="/usr/lib/systemd/system/nginx.service"

# --- 1. 清理系统原有nginx ---
echo "=== 1. 停止并清理原有nginx ==="
systemctl stop nginx 2>/dev/null
pkill -9 nginx 2>/dev/null
sleep 2

dnf remove -y nginx nginx-all-modules nginx-filesystem nginx-mod-* 2>/dev/null
yum remove -y nginx nginx-all-modules nginx-filesystem nginx-mod-* 2>/dev/null

groupdel ${group} 2>/dev/null
userdel -r ${user} 2>/dev/null

rm -rf /etc/nginx /usr/share/nginx /var/log/nginx /var/cache/nginx /var/lib/nginx
rm -rf /run/nginx /run/php-fpm /var/run/nginx /usr/local/nginx /tmp/nginx*
rm -f /usr/sbin/nginx /usr/local/sbin/nginx /usr/bin/nginx /usr/local/bin/nginx
rm -f /etc/systemd/system/nginx.service /usr/lib/systemd/system/nginx.service /lib/systemd/system/nginx.service
systemctl daemon-reload 2>/dev/null
rm -f /etc/sysconfig/nginx /etc/default/nginx /etc/profile.d/nginx.sh
rm -rf /usr/share/man/man8/nginx* /usr/share/man/man1/nginx*
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
mkdir -p /var/nginx/proxy_cache  # proxy_cache 目录

# --- 8. 修改权限 ---
echo "=== 8. 设置权限 ==="
chown -R ${user}:${group} ${prefix}
chown ${user}:${group} ${prefix}/run
chown -R ${user}:${group} /var/nginx

# --- 9. 生成主配置文件 ---
echo "=== 9. 生成主配置文件 ==="
cat > ${conf_file} << 'EOFCONF'
user nginx nginx;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 100000;
error_log logs/error.log warn;
pid run/nginx.pid;

events {
    use epoll;
    worker_connections 65535;
    multi_accept on;
    accept_mutex on;
    accept_mutex_delay 500ms;
}

http {
    include mime.types;
    include /data/soft/nginx/conf/conf.d/*.conf;
    default_type application/octet-stream;

    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log logs/access.log main;

    # 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 10000;
    keepalive_disable msie6;
    types_hash_max_size 2048;

    client_header_timeout 15;
    client_body_timeout 15;
    send_timeout 15;
    lingering_timeout 5;
    client_max_body_size 10m;

    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss image/svg+xml;
    gzip_min_length 1k;
    gzip_buffers 16 8k;

    # 代理缓存
    proxy_cache_path /var/nginx/proxy_cache levels=1:2 keys_zone=proxy_cache:100m inactive=7d max_size=10g;

    # 限流配置
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    # ==== HTTP 80 server ====
    server {
        listen 80 default_server;
        server_name _;
        root html;
        index index.html index.htm;

        location / {
            try_files $uri $uri/ =404;
        }

        location /api/ {
            limit_req zone=req_limit burst=20 nodelay;
            limit_conn conn_limit 100;
            proxy_pass http://backend_server;
            proxy_cache proxy_cache;
            proxy_cache_key "$scheme$request_method$host$request_uri";
            proxy_cache_valid 200 304 7d;
            proxy_cache_valid any 1m;
            proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
        }

        # 静态资源优化
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2|woff|ttf)$ {
            root /data/static;
            expires 30d;
            add_header Cache-Control "public, immutable";
            access_log off;
            log_not_found off;
            gzip on;
        }

        # 大文件下载优化
        location ~* \.(iso|zip|tar\.gz|mp4)$ {
            root /data/download;
            expires 7d;
            add_header Accept-Ranges bytes;
            sendfile on;
            tcp_nopush on;
        }
    }

    # ==== HTTPS 443 server ====
    #server {
    #    listen 443 ssl http2;
    #    ssl_protocols TLSv1.2 TLSv1.3;
    #    ssl_prefer_server_ciphers on;
    #   ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    #    ssl_session_cache shared:SSL:10m;
    #   ssl_session_timeout 1d;
    #   ssl_session_tickets on;
    #   ssl_stapling on;
    #   ssl_stapling_verify on;
    #   resolver 8.8.8.8 1.1.1.1 valid=300s;
   # }

    # 包含虚拟主机配置
    include conf/conf.d/*.conf;
}

# ==== Stream 四层代理 ====
#stream {
#    server {
#        listen 3306;
#        proxy_pass 127.0.0.1:3306;
#    }
    
#    server {
#        listen 6379;
#        proxy_pass 127.0.0.1:6379;
#    }
#}
EOFCONF

# --- 10. 生成默认虚拟主机配置 ---
echo "=== 10. 生成默认虚拟主机 ==="
cat > ${prefix}/conf/conf.d/vhost.conf << 'EOFVHOST'
server {
    listen 80 default_server;
    server_name _;

    root /data/soft/nginx/web1;
    index index.php;

    location / {
        autoindex on;
    }

    location ~ \.php$ {
        fastcgi_pass phpserver;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
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
ss -tlnp | grep nginx
