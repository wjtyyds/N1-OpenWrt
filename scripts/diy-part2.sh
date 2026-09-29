#!/bin/bash
# diy-part2.sh

# ==========================================
# 0. 获取最新 Tag 克隆函数 (已强化鉴权与日志)
# ==========================================
clone_latest_tag() {
    local repo_url=$1
    local dest_dir=$2
    local api_url="https://api.github.com/repos/${repo_url#https://github.com/}/releases/latest"

    echo "查询 $dest_dir 最新 Tag..."
    local api_resp=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "$api_url")
    local latest_tag=$(echo "$api_resp" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -n "$latest_tag" ]; then
        echo "✅ 成功解析到 $dest_dir 最新 Tag: $latest_tag，正在克隆..."
        git clone --branch "$latest_tag" --depth 1 "$repo_url" "package/custom/$dest_dir"
    else
        echo "❌ 未能从 API 解析到 $dest_dir 的 Tag！API 响应详情："
        echo "$api_resp" | head -n 15
        echo "⚠️ 强制回退，正在拉取默认分支最新代码..."
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
        # 把 hysteria 等核心组件加进来，让系统彻底 uninstall 解除软链接
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${lede_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
        # 循环中一并斩断 helloworld 下的同名包
        rm -rf feeds/helloworld/"$plugin" 2>/dev/null
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    # 把 helloworld 库里的老底彻底抄掉
    rm -rf feeds/helloworld/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null
    rm -rf feeds/luci/applications/luci-app-passwall

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/wjtyyds/luci-app-lucky.git package/custom/lucky
    git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    echo "正在获取 OpenClash 最新版本..."
    OPENCLASH_RESP=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/vernesong/OpenClash/releases/latest")
    OPENCLASH_TAG=$(echo "$OPENCLASH_RESP" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    if [ -n "$OPENCLASH_TAG" ]; then
        echo "✅ 成功获取 OpenClash Tag: $OPENCLASH_TAG"
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        echo "❌ 获取 OpenClash Tag 失败！API响应前15行："
        echo "$OPENCLASH_RESP" | head -n 15
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

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
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${immortalwrt_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/wjtyyds/luci-app-lucky.git package/custom/lucky
    git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    echo "正在获取 OpenClash 最新版本..."
    OPENCLASH_RESP=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/vernesong/OpenClash/releases/latest")
    OPENCLASH_TAG=$(echo "$OPENCLASH_RESP" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    if [ -n "$OPENCLASH_TAG" ]; then
        echo "✅ 成功获取 OpenClash Tag: $OPENCLASH_TAG"
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        echo "❌ 获取 OpenClash Tag 失败！API响应前15行："
        echo "$OPENCLASH_RESP" | head -n 15
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

elif [ "$FIRMWARE_TYPE" == "openwrt" ]; then
    echo "====== 开始执行 官方 OpenWrt 专属定制 ======"

    # 💡 [选项1]：完整替换 Docker 引擎以适配对应分支
    if [[ "$SOURCE_BRANCH" =~ ^v([0-9]+\.[0-9]+) ]]; then
        IMM_PKG_BRANCH="openwrt-${BASH_REMATCH[1]}"
    else
        IMM_PKG_BRANCH="master"
    fi

    echo "--- 正在从 immortalwrt/packages 的 $IMM_PKG_BRANCH 分支完整替换 Docker 组件引擎 ---"
    rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose}
    git clone -b "$IMM_PKG_BRANCH" --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
    cp -r /tmp/imm_packages/utils/{docker,dockerd,containerd,runc,docker-compose} feeds/packages/utils/ || true
    rm -rf /tmp/imm_packages

    openwrt_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${openwrt_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman
    git clone --depth 1 https://github.com/wjtyyds/luci-app-lucky.git package/custom/lucky
    git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    echo "正在获取 OpenClash 最新版本..."
    OPENCLASH_RESP=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/vernesong/OpenClash/releases/latest")
    OPENCLASH_TAG=$(echo "$OPENCLASH_RESP" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    if [ -n "$OPENCLASH_TAG" ]; then
        echo "✅ 成功获取 OpenClash Tag: $OPENCLASH_TAG"
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        echo "❌ 获取 OpenClash Tag 失败！API响应前15行："
        echo "$OPENCLASH_RESP" | head -n 15
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

# 💡 命名为 zz_custom_setup 保证全系统最后一个执行，绝对秒杀 LEDE 祖传跑分 (传承 09 基底的防爆设计)
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