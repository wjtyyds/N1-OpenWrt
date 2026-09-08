#!/bin/bash
# diy-part2.sh

# ==========================================
# 1. 斩断内置冲突插件
# ==========================================
conflict_plugins=(
    "adguardhome" "luci-app-adguardhome"
    "luci-app-openclash" "openclash"
    "oaf" "kmod-oaf" "appfilter" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
    "lucky" "luci-app-lucky"
    "luci-app-dockerman"
)
for plugin in "${conflict_plugins[@]}"; do
    ./scripts/feeds uninstall "$plugin" || true
    rm -rf feeds/packages/*/*/"$plugin"
    rm -rf feeds/luci/*/*/"$plugin"
done

# ==========================================
# 仅针对 ImmortalWrt 的 Rust 404 专项修复 (暴力替换为官方源码)
# ==========================================
#if [ "$FIRMWARE_TYPE" == "immortalwrt" ]; then
#    echo "为避免 Rust CI 404 报错，正在拉取 OpenWrt 官方 Rust 源码替换..."
#    rm -rf feeds/packages/lang/rust
#    git clone --depth 1 https://github.com/openwrt/packages.git /tmp/openwrt_packages
#    cp -r /tmp/openwrt_packages/lang/rust feeds/packages/lang/
#    rm -rf /tmp/openwrt_packages
#fi

# ==========================================
# 2. 获取最新 Tag 克隆函数
# ==========================================
clone_latest_tag() {
    local repo_url=$1
    local dest_dir=$2
    local api_url="https://api.github.com/repos/${repo_url#https://github.com/}/releases/latest"
    local latest_tag=$(curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -n "$latest_tag" ]; then
        git clone --branch "$latest_tag" --depth 1 "$repo_url" "package/custom/$dest_dir"
    else
        git clone --depth 1 "$repo_url" "package/custom/$dest_dir"
    fi
}

mkdir -p package/custom

# 拉取普通插件
clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
clone_latest_tag "https://github.com/gdy666/luci-app-lucky" "lucky"
clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

# 稀疏克隆 OpenClash
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

# 常规拉取无 Tag 插件
git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/custom/luci-app-adguardhome

# --- 动态判断是否需要拉取 Docker 相关组件 ---
if [ "$BUILD_TYPE" == "public" ]; then
    echo "【公共版】：开始拉取 Docker 与 Dockerman 组件..."
    git clone --depth 1 https://github.com/wjtyyds/luci-app-dockerman.git package/custom/luci-app-dockerman
    git clone --depth 1 https://github.com/wjtyyds/luci-lib-docker.git package/custom/luci-lib-docker
else
    echo "【私有版】：无需 Docker，跳过相关组件拉取..."
fi

# 针对特定固件
if [ "$FIRMWARE_TYPE" == "openwrt" ]; then
    git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman
    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
    bash add_turboacc.sh --no-sfe
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

if [ "$FIRMWARE_TYPE" == "lede" ]; then
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