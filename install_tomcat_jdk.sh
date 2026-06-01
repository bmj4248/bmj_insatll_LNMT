#!/bin/bash
#==================================================
# JDK + Tomcat 安装脚本
# 修改顶部变量即可更换版本
#==================================================

# ---------- 版本变量（只需修改这里）----------
JDK_TAR="jdk-11.0.16_linux-x64_bin.tar.gz"
JDK_DIR="jdk-11.0.16"

TOMCAT_TAR="apache-tomcat-10.1.33.tar.gz"
TOMCAT_DIR="apache-tomcat-10.1.33"

# ---------- 路径变量 ----------
JDK_INSTALL="/usr/local/src"
TOMCAT_INSTALL="/data/soft"
TOMCAT_LINK="/data/soft/tomcat"

#==================================================
# 开始安装
#==================================================

# 1. 检查安装包
echo ">>> 检查安装包..."
[ ! -f "$JDK_TAR" ] && echo "错误: $JDK_TAR 不存在" && exit 1
[ ! -f "$TOMCAT_TAR" ] && echo "错误: $TOMCAT_TAR 不存在" && exit 1
echo ">>> 安装包检查通过"

# 2. 安装 JDK
echo ">>> 安装 JDK..."
mkdir -p $JDK_INSTALL
tar -zxvf $JDK_TAR -C $JDK_INSTALL/

cat > /etc/profile.d/jdk.sh << EOF
export JAVA_HOME=$JDK_INSTALL/$JDK_DIR
export PATH=\$JAVA_HOME/bin:\$PATH
export CLASSPATH=.:\$JAVA_HOME/lib
EOF

source /etc/profile.d/jdk.sh
java -version
echo ">>> JDK 安装完成"

# 3. 安装 Tomcat
echo ">>> 安装 Tomcat..."
mkdir -p $TOMCAT_INSTALL
tar -zxvf $TOMCAT_TAR -C $TOMCAT_INSTALL/

ln -sf $TOMCAT_INSTALL/$TOMCAT_DIR $TOMCAT_LINK
echo ">>> Tomcat 解压并创建软链接完成"

# 4. 创建 tomcat 用户
echo ">>> 创建 tomcat 用户..."
id tomcat &>/dev/null || useradd -r -s /sbin/nologin tomcat

chown -R tomcat:tomcat $TOMCAT_LINK
chown -R tomcat:tomcat $TOMCAT_LINK/*
echo ">>> 用户创建并授权完成"

# 5. 配置 Tomcat 环境变量
echo ">>> 配置环境变量..."
cat > /etc/profile.d/tomcat.sh << EOF
export CATALINA_HOME=$TOMCAT_LINK
export CATALINA_BASE=$TOMCAT_LINK
export PATH=\$CATALINA_HOME/bin:\$PATH
EOF

source /etc/profile.d/tomcat.sh
echo ">>> 环境变量配置完成"

# 6. 创建 systemd 服务
echo ">>> 创建 systemd 服务..."
cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat
After=network.target

[Service]
Type=forking
Environment=JAVA_HOME=$JDK_INSTALL/$JDK_DIR
Environment=CATALINA_HOME=$TOMCAT_LINK
Environment=CATALINA_BASE=$TOMCAT_LINK
Environment=CATALINA_PID=$TOMCAT_LINK/temp/tomcat.pid

ExecStart=$TOMCAT_LINK/bin/startup.sh
ExecStop=$TOMCAT_LINK/bin/shutdown.sh

User=tomcat
Group=tomcat

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tomcat
echo ">>> systemd 服务创建完成"

# 7. 启动服务
echo ">>> 启动 Tomcat..."
systemctl start tomcat
sleep 3

# 8. 检查状态
if systemctl is-active --quiet tomcat; then
    echo ">>> Tomcat 启动成功！"
    echo ">>> 访问地址: http://$(hostname -I | awk '{print $1}'):8080"
else
    echo ">>> Tomcat 启动失败，请检查日志: $TOMCAT_LINK/logs/catalina.out"
fi

# 9. 输出信息
echo ""
echo "=================================================="
echo "安装完成！"
echo "=================================================="
echo "JDK 路径: $JDK_INSTALL/$JDK_DIR"
echo "Tomcat 路径: $TOMCAT_INSTALL/$TOMCAT_DIR"
echo "Tomcat 软链接: $TOMCAT_LINK"
echo "JDK 环境变量: /etc/profile.d/jdk.sh"
echo "Tomcat 环境变量: /etc/profile.d/tomcat.sh"
echo "服务文件: /etc/systemd/system/tomcat.service"
echo "启动: systemctl start tomcat"
echo "停止: systemctl stop tomcat"
echo "重启: systemctl restart tomcat"
echo "状态: systemctl status tomcat"
echo "=================================================="