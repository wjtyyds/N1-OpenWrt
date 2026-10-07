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
        "luci-app-dockerman" "luci-lib-docker"
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${lede_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
        rm -rf feeds/helloworld/"$plugin" 2>/dev/null
    done

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 与 代理组件..."
        # 斩草除根 Docker
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        # 挫骨扬灰 代理源
        rm -rf feeds/helloworld 2>/dev/null
        rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/wjtyyds/luci-app-lucky.git package/custom/lucky

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

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

    # 特殊修复：immortalwrt 的 rust 依赖
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
        "luci-app-dockerman" "luci-lib-docker"
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${immortalwrt_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
        rm -rf feeds/helloworld/"$plugin" 2>/dev/null
    done

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 与 代理组件..."
        # 斩草除根 Docker
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        # 挫骨扬灰 代理源
        rm -rf feeds/helloworld 2>/dev/null
        rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/wjtyyds/luci-app-lucky.git package/custom/lucky

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

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

    openwrt_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
        "luci-app-dockerman" "luci-lib-docker"
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${openwrt_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
        rm -rf feeds/helloworld/"$plugin" 2>/dev/null
    done

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 与 代理组件..."
        # 斩草除根 Docker
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        # 挫骨扬灰 代理源
        rm -rf feeds/helloworld 2>/dev/null
        rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman
    git clone --depth 1 https://github.com/wjtyyds/luci-app-lucky.git package/custom/lucky

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

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

# 💡 命名为 zz_custom_setup 保证全系统最后一个执行，绝对秒杀 LEDE 祖传跑分
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/zz_custom_setup
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

# 2. 极致洁癖的 sysctl 注入
sed -i '/net.bridge.bridge-nf-call/d' /etc/sysctl.conf
cat << 'SYSCTL_EOF' >> /etc/sysctl.conf

# Network routing & bridge optimization
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-arptables=0
SYSCTL_EOF
sysctl -p

# 3. 设置 AdGuardHome 标准路径
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null

# 4. 彻底清理 LEDE 祖传的跑分计划任务 (全网最稳的末位清理法)
sed -i '/coremark/d' /etc/crontabs/root 2>/dev/null
/etc/init.d/cron restart 2>/dev/null

# 脚本使命完成，自毁
rm -f /etc/uci-defaults/zz_custom_setup
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