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
# 0.5 修复 Xray-core 依赖的 Golang 版本过低问题
# ==========================================
echo "正在替换 Golang 源码为最新版本..."
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang

./scripts/feeds install -a -f

# ==========================================
# 1. 核心大分流：各源码隔离操作 (插件卸载与拉取)
# ==========================================

# ----------------- [ LEDE 源码专属逻辑 ] -----------------
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

# ----------------- [ ImmortalWrt 源码专属逻辑 ] -----------------
elif [ "$FIRMWARE_TYPE" == "immortalwrt" ]; then
    echo "====== 开始执行 ImmortalWrt 专属定制 ======"

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

    # 💡 [针对 ImmortalWrt 报错新增]：替换最新的 docker-compose 源码以适配新版 Golang
    echo "--- 正在修复 docker-compose 编译兼容性 ---"
    rm -rf feeds/packages/utils/docker-compose
    git clone --depth 1 https://github.com/openwrt/packages.git /tmp/ow_packages
    cp -r /tmp/ow_packages/utils/docker-compose feeds/packages/utils/
    rm -rf /tmp/ow_packages

    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

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

# ----------------- [ 官方 OpenWrt 源码专属逻辑 ] -----------------
elif [ "$FIRMWARE_TYPE" == "openwrt" ]; then
    echo "====== 开始执行 官方 OpenWrt 专属定制 ======"

    # 💡 [补全替换]：把 docker-compose 也加入强制更新阵容
    echo "--- 正在完整替换 Docker 组件 ---"
    rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose}
    git clone --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
    cp -r /tmp/imm_packages/utils/{docker,dockerd,containerd,runc,docker-compose} feeds/packages/utils/
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
# 2. 本地化环境与隐蔽自启服务注入
# ==========================================
FILES_DIR="package/base-files/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/etc/init.d
mkdir -p ${FILES_DIR}/etc/rc.d

# 【核心暗杀服务】：U盘不动如山，eMMC搬运后彻底自杀抹除痕迹
cat << 'EOF' > ${FILES_DIR}/etc/init.d/n1_core_init
#!/bin/sh /etc/rc.common
START=99

start() {
    (
        sleep 3
        ROOT_DEV=$(mount | grep ' /rom ' | awk '{print $1}')
        [ -z "$ROOT_DEV" ] && ROOT_DEV=$(mount | grep -E ' / ' | awk '{print $1}')

        if echo "$ROOT_DEV" | grep -q "mmcblk"; then
            if [ -x /etc/init.d/dockerd ]; then
                /etc/init.d/dockerd enable
                /etc/init.d/dockerd start
            fi

            # AdGuardHome 专属路径搬运（绝不更改你的设计）
            if [ -f /usr/lib/.adg_core_tmp ]; then
                mkdir -p /mnt/mmcblk2p4/AdGuardHome
                mv /usr/lib/.adg_core_tmp /mnt/mmcblk2p4/AdGuardHome/AdGuardHome
                chmod 755 /mnt/mmcblk2p4/AdGuardHome/AdGuardHome
            fi

            # 搬运完成后抹杀自己
            rm -f /etc/init.d/n1_core_init
            rm -f /etc/rc.d/S99n1_core_init
        else
            if [ -x /etc/init.d/dockerd ]; then
                /etc/init.d/dockerd disable
                /etc/init.d/dockerd stop 2>/dev/null
            fi
        fi
    ) &
}
EOF
chmod +x ${FILES_DIR}/etc/init.d/n1_core_init
ln -s ../init.d/n1_core_init ${FILES_DIR}/etc/rc.d/S99n1_core_init


# --- 基础配置与网桥优化脚本 (对所有人通用) ---
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99_custom_setup
#!/bin/sh
if [ -f /root/oaf.ko ]; then
    KVER=$(uname -r)
    mkdir -p /lib/modules/$KVER
    mv /root/oaf.ko /lib/modules/$KVER/
    depmod -a
    echo "oaf" > /etc/modules.d/99-oaf
    modprobe oaf
fi

# 极其隐蔽地追加网桥防丢包参数到底层文件
cat << 'SYSCTL_EOF' >> /etc/sysctl.conf

# Network routing & bridge optimization
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-arptables=0
SYSCTL_EOF
sysctl -p
EOF

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/99_custom_setup
uci delete uhttpd.main.listen_https 2>/dev/null
uci commit uhttpd 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
EOF
fi

# 你的专属配置路径（绝对保留）
cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/99_custom_setup
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null
EOF

if [ "$BUILD_TYPE" == "personal" ]; then
    cat << EOF >> ${FILES_DIR}/etc/uci-defaults/99_custom_setup
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
EOF
fi