#!/bin/bash
# diy-part2.sh

# ==========================================
# 0. 获取最新 Tag 克隆函数
# ==========================================
clone_latest_tag() {
    local repo_url=$1
    local dest_dir=$2
    local api_url="https://api.github.com/repos/${repo_url#https://github.com/}/releases/latest"
    local latest_tag=$(curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -n "$latest_tag" ]; then
        echo "发现最新 Tag: $latest_tag，正在克隆..."
        git clone --branch "$latest_tag" --depth 1 "$repo_url" "package/custom/$dest_dir"
    else
        echo "未发现 Release Tag，拉取默认分支最新代码..."
        git clone --depth 1 "$repo_url" "package/custom/$dest_dir"
    fi
}

mkdir -p package/custom

# ==========================================
# 0.5 锁定 Golang 版本，修复 Xray-core 编译报错
# ==========================================
echo "正在替换 Golang 源码为 27.x (Go 1.27) 稳定版本..."
rm -rf feeds/packages/lang/golang
git clone -b 27.x --depth 1 https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang

./scripts/feeds install -a -f

# ==========================================
# 1. 核心大分流：各源码隔离操作 (插件卸载与拉取)
# ==========================================

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    echo "====== 开始执行 LEDE 专属定制 ======"

    lede_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
    )
    for plugin in "${lede_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    # OpenClash 拉取逻辑
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG=$(curl -s "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    if [ -n "$OPENCLASH_TAG" ]; then
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

elif [ "$FIRMWARE_TYPE" == "immortalwrt" ]; then
    echo "====== 开始执行 ImmortalWrt 专属定制 ======"

    # 💡 落实选项 1：解决 containerd 等与 Go 1.27 的链接报错
    echo "--- 正在完整替换 Docker 组件引擎以适配 Go 1.27 ---"
    rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose}
    git clone --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
    cp -r /tmp/imm_packages/utils/{docker,dockerd,containerd,runc,docker-compose} feeds/packages/utils/ || true
    rm -rf /tmp/imm_packages

    if [ "$SOURCE_BRANCH" == "v25.12.1" ]; then
        rm -rf feeds/packages/lang/rust
        git clone --depth 1 https://github.com/openwrt/packages.git /tmp/openwrt_packages
        cp -r /tmp/openwrt_packages/lang/rust feeds/packages/lang/
        rm -rf /tmp/openwrt_packages
    fi

    immortalwrt_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
    )
    for plugin in "${immortalwrt_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    # OpenClash 拉取逻辑
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG=$(curl -s "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    if [ -n "$OPENCLASH_TAG" ]; then
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

elif [ "$FIRMWARE_TYPE" == "openwrt" ]; then
    echo "====== 开始执行 官方 OpenWrt 专属定制 ======"

    # 💡 落实选项 1：解决 containerd 等与 Go 1.27 的链接报错
    echo "--- 正在完整替换 Docker 组件引擎以适配 Go 1.27 ---"
    rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose}
    git clone --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
    cp -r /tmp/imm_packages/utils/{docker,dockerd,containerd,runc,docker-compose} feeds/packages/utils/ || true
    rm -rf /tmp/imm_packages

    openwrt_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
    )
    for plugin in "${openwrt_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    # OpenClash 拉取逻辑
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG=$(curl -s "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    if [ -n "$OPENCLASH_TAG" ]; then
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
    bash add_turboacc.sh --no-sfe
fi

if [ "$BUILD_TYPE" == "public" ]; then
    echo "【公共版】：使用源码集成的 Docker 与 Dockerman 组件..."
else
    echo "【私有版】：无需 Docker，跳过相关组件拉取..."
fi

# ==========================================
# 2. 本地化环境与守护脚本注入
# ==========================================
FILES_DIR="package/base-files/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/etc/init.d

# 💡【核心防死链与调度脚本】：动态挂载点识别 + eMMC 骨灰级自毁
cat << 'EOF' > ${FILES_DIR}/etc/init.d/core_init
#!/bin/sh /etc/rc.common
# 设为17，优先级极高，赶在 AdGuardHome 等服务启动前完成调度
START=17

start() {
    # 1. 动态获取真实数据盘挂载点 (U盘通常为 sda4, eMMC为 mmcblk2p4)
    DATA_DIR=""
    if [ -d /mnt/mmcblk2p4 ]; then
        DATA_DIR="/mnt/mmcblk2p4"
    elif [ -d /mnt/sda4 ]; then
        DATA_DIR="/mnt/sda4"
    fi

    # 2. ADG 核心下发与动态软链机制
    if [ -n "$DATA_DIR" ]; then
        mkdir -p $DATA_DIR/AdGuardHome
        # 只要存在备用核心库，就覆盖过去 (保障不管是U盘还是新写的eMMC，第一次都能拿最新版)
        if [ -f /usr/lib/core_backup/AdGuardHome_core ]; then
            cp -f /usr/lib/core_backup/AdGuardHome_core $DATA_DIR/AdGuardHome/AdGuardHome
            chmod 755 $DATA_DIR/AdGuardHome/AdGuardHome
        fi

        # 暴力清理死掉的软链或遗留文件，创建指向动态数据盘的新软链
        rm -rf /usr/bin/AdGuardHome
        ln -sf $DATA_DIR/AdGuardHome /usr/bin/AdGuardHome
    fi

    # 3. Lucky 核心开机覆盖
    if [ -f /usr/lib/core_backup/lucky ]; then
        cp -f /usr/lib/core_backup/lucky /usr/bin/lucky
        chmod 755 /usr/bin/lucky
    fi

    # 4. 判断是否为 eMMC 启动，执行“阅后即焚”
    ROOT_PART=$(df -h / | tail -n1 | awk '{print $1}')
    if echo "$ROOT_PART" | grep -q "mmcblk"; then
        # 真实 eMMC 落地完毕，销毁备用核心库以节省空间
        rm -rf /usr/lib/core_backup

        # 销毁脚本自己及启动项，真正做到完全无痕
        rm -f /etc/init.d/core_init
        rm -f /etc/rc.d/S17core_init
    fi
}
EOF
chmod +x ${FILES_DIR}/etc/init.d/core_init
# 设置开机自启
ln -s ../init.d/core_init ${FILES_DIR}/etc/rc.d/S17core_init


# --- 基础配置优化脚本 ---
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99_custom_setup
#!/bin/sh

# 1. OAF 模块加载
if [ -f /root/oaf.ko ]; then
    KVER=$(uname -r)
    mkdir -p /lib/modules/$KVER
    mv /root/oaf.ko /lib/modules/$KVER/
    depmod -a
    echo "oaf" > /etc/modules.d/99-oaf
    modprobe oaf
fi

# 2. 极致洁癖的 sysctl 注入（无论有无旧配置，先清理干净，再追加！）
sed -i '/net.bridge.bridge-nf-call/d' /etc/sysctl.conf
cat << 'SYSCTL_EOF' >> /etc/sysctl.conf

# Network routing & bridge optimization
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-arptables=0
SYSCTL_EOF
sysctl -p

# 3. 设置 AdGuardHome 标准路径
# 核心和工作目录全部指向软链接，由 core_init 在底层负责软链的真实验证
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null

# 脚本使命完成，自毁
rm -f /etc/uci-defaults/99_custom_setup
EOF

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/98_lede_setup
#!/bin/sh
uci delete uhttpd.main.listen_https 2>/dev/null
uci commit uhttpd 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
rm -f /etc/uci-defaults/98_lede_setup
EOF
fi

if [ "$BUILD_TYPE" == "personal" ]; then
    cat << EOF > ${FILES_DIR}/etc/uci-defaults/97_personal_setup
#!/bin/sh
uci delete network.lan.type 2>/dev/null
uci set network.lan.device='eth0'
uci set network.lan.ifname='eth0'
uci set network.lan.proto='static'
uci delete network.lan.ipaddr
uci add_list network.lan.ipaddr='192.168.2.254/24'
uci set network.lan.gateway='192.168.2.1'
uci delete network.lan.dns
uci add_list network.lan.dns='192.168.2.1'

uci set network.wan=interface
uci set network.wan.proto='pppoe'
uci set network.wan.device='eth0'
uci set network.wan.ifname='eth0'
uci set network.wan.username='${PPPOE_USER}'
uci set network.wan.password='${PPPOE_PASS}'
uci set network.wan.ipv6='auto'
uci set network.wan.norelease='1'
uci set network.wan.multipath='off'
uci commit network

mkdir -p /etc/crontabs
if ! grep -q "drop_caches" /etc/crontabs/root 2>/dev/null; then
    echo "0 22 * * * sync; echo 3 > /proc/sys/vm/drop_caches" >> /etc/crontabs/root
fi

uci set AdGuardHome.AdGuardHome.configpath='/etc/AdGuardHome.yaml'
uci commit AdGuardHome
rm -f /etc/uci-defaults/97_personal_setup
EOF
fi