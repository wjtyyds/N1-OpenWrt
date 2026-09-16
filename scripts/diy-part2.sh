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

# 【注意！新增下面这一行！】强制刷新软链接，确保替换生效
./scripts/feeds install -a -f

# ==========================================
# 1. 核心大分流：各源码隔离操作 (插件卸载与拉取)
# ==========================================

# ----------------- [ LEDE 源码专属逻辑 ] -----------------
if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    echo "====== 开始执行 LEDE 专属定制 ======"

    # 1. 斩断内置冲突插件
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

    # 移除 openwrt feeds 自带的核心库与过时 luci 版本
    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    # 2. 常规拉取无 Tag 插件
    echo "--- 拉取无 Tag 要求的最新代码 ---"
    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    # 3. 自动寻找最新 Tag 并拉取
    echo "--- 自动寻找最新的 Release Tag ---"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    # 4. 稀疏克隆 OpenClash
    echo "--- 稀疏克隆 OpenClash ---"
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG=$(curl -s "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout

    if [ -n "$OPENCLASH_TAG" ]; then
        echo "发现 OpenClash 最新 Tag: $OPENCLASH_TAG，开始稀疏拉取..."
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        echo "未获取到 OpenClash Tag，后备拉取 master 分支..."
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

# ----------------- [ ImmortalWrt 源码专属逻辑 ] -----------------
elif [ "$FIRMWARE_TYPE" == "immortalwrt" ]; then
    echo "====== 开始执行 ImmortalWrt 专属定制 ======"

    # 仅针对 ImmortalWrt v25.12.1 的 Rust 404 专项修复
    if [ "$SOURCE_BRANCH" == "v25.12.1" ]; then
        echo "检测到正在编译 ImmortalWrt v25.12.1，为避免 Rust CI 404 报错，正在拉取 OpenWrt 官方 Rust 源码替换..."
        rm -rf feeds/packages/lang/rust
        git clone --depth 1 https://github.com/openwrt/packages.git /tmp/openwrt_packages
        cp -r /tmp/openwrt_packages/lang/rust feeds/packages/lang/
        rm -rf /tmp/openwrt_packages
    else
        echo "当前版本 ($SOURCE_BRANCH) 无需执行 Rust 404 修复，已跳过。"
    fi

    # 1. 斩断内置冲突插件 (只斩你需要替换的，保留自带 diskman 和 dockerman)
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

    # 移除 feeds 自带的核心库与过时 luci 版本
    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    # 2. 常规拉取无 Tag 插件
    echo "--- 拉取无 Tag 要求的最新代码 ---"
    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    # 3. 自动寻找最新 Tag 并拉取
    echo "--- 自动寻找最新的 Release Tag ---"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    # 4. 稀疏克隆 OpenClash
    echo "--- 稀疏克隆 OpenClash ---"
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG=$(curl -s "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout

    if [ -n "$OPENCLASH_TAG" ]; then
        echo "发现 OpenClash 最新 Tag: $OPENCLASH_TAG，开始稀疏拉取..."
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        echo "未获取到 OpenClash Tag，后备拉取 master 分支..."
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

# ----------------- [ 官方 OpenWrt 源码专属逻辑 ] -----------------
elif [ "$FIRMWARE_TYPE" == "openwrt" ]; then
    echo "====== 开始执行 官方 OpenWrt 专属定制 ======"

    # 【新增】借用 ImmortalWrt 的 containerd 以兼容新版 Golang
    echo "--- 正在替换 containerd 源码以修复 Golang 兼容性 ---"
    rm -rf feeds/packages/utils/containerd
    git clone --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
    cp -r /tmp/imm_packages/utils/containerd feeds/packages/utils/
    rm -rf /tmp/imm_packages
    
    # 1. 斩断内置冲突插件
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

    # 移除 openwrt feeds 自带的核心库与过时 luci 版本
    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    # 2. 常规拉取无 Tag 插件
    echo "--- 拉取无 Tag 要求的最新代码 ---"
    git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
    git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman
    git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages

    # 3. 自动寻找最新 Tag 并拉取
    echo "--- 自动寻找最新的 Release Tag ---"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"

    # 4. 稀疏克隆 OpenClash
    echo "--- 稀疏克隆 OpenClash ---"
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG=$(curl -s "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout

    if [ -n "$OPENCLASH_TAG" ]; then
        echo "发现 OpenClash 最新 Tag: $OPENCLASH_TAG，开始稀疏拉取..."
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        echo "未获取到 OpenClash Tag，后备拉取 master 分支..."
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

    # 5. 添加 Turboacc
    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
    bash add_turboacc.sh --no-sfe
fi

# ==========================================
# 2. 动态判断 Docker (全部源码共用逻辑)
# ==========================================
if [ "$BUILD_TYPE" == "public" ]; then
    echo "【公共版】：使用源码集成的 Docker 与 Dockerman 组件..."
else
    echo "【私有版】：无需 Docker，跳过相关组件拉取..."
fi

# ==========================================
# 3. 本地化环境与定制配置合并 (降维打击)
# ==========================================
echo "====== 开始组装底层定制文件 ======"
FILES_DIR="package/base-files/files"
IMPORT_DIR="$GITHUB_WORKSPACE/auto_import"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/usr/bin
mkdir -p ${FILES_DIR}/root
mkdir -p ${FILES_DIR}/etc

# --- 部署素材库中的核心文件 (仅限公共版) ---
if [ "$BUILD_TYPE" == "public" ] && [ -d "$IMPORT_DIR" ]; then
    if [ -f "${IMPORT_DIR}/lucky" ]; then
        cp "${IMPORT_DIR}/lucky" "${FILES_DIR}/root/lucky_tmp" || true
    fi
fi

# --- 基础配置脚本 (对所有人通用) ---
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99_custom_setup
#!/bin/sh

# A. 挂载 OAF 模块
if [ -f /root/oaf.ko ]; then
    KVER=$(uname -r)
    mkdir -p /lib/modules/$KVER
    mv /root/oaf.ko /lib/modules/$KVER/
    depmod -a
    echo "oaf" > /etc/modules.d/99-oaf
    modprobe oaf
fi
EOF

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/99_custom_setup
# B. 修复 UHTTPD HTTPS (仅限 Lede 固件)
uci delete uhttpd.main.listen_https 2>/dev/null
uci commit uhttpd 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
EOF
fi

cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/99_custom_setup
# C. AdGuardHome 通用核心路径设置
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null
EOF

# --- 个人隐私与独立逻辑分配 ---
if [ "$BUILD_TYPE" == "personal" ]; then
    echo "当前是【个人分支】：注入隐私与宽带拨号..."
    
    cat << EOF >> ${FILES_DIR}/etc/uci-defaults/99_custom_setup
# 注入个人宽带
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

# 定时清理任务
mkdir -p /etc/crontabs
if ! grep -q "drop_caches" /etc/crontabs/root 2>/dev/null; then
    echo "0 22 * * * sync; echo 3 > /proc/sys/vm/drop_caches" >> /etc/crontabs/root
fi

# 设置 AdGuardHome 隐私配置路径
uci set AdGuardHome.AdGuardHome.configpath='/etc/AdGuardHome.yaml'
uci commit AdGuardHome
EOF

else
    echo "当前是【网友分支】：保持纯净，无个人隐私..."
fi