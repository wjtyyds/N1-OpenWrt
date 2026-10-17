#!/bin/bash
# diy-part2.sh

# ==========================================
# 0. 获取最新 Tag 克隆函数 (保留给 OAF 和 Aurora 使用)
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
# 0.5. 提取公共逻辑：Golang 升级
# ==========================================
if [[ "$FIRMWARE_TYPE" != lede* ]] && [ "$BUILD_TYPE" != "personal" ]; then
    echo "【Public 编译专属】：为 OpenWrt，ImmortalWrt，iStoreOS 升级 Golang 1.27..."
    rm -rf feeds/packages/lang/golang
    git clone -b 27.x --depth 1 https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang
    ./scripts/feeds install -a -f
fi

# ==========================================
# 1. 核心大分流：各源码隔离操作 (插件卸载与拉取)
# ==========================================

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    echo "====== 开始执行 LEDE 专属定制 ======"

    lede_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-oaf" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${lede_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 与 剩余代理组件..."
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        rm -rf feeds/helloworld 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome

    # 【锁定版本】Lucky 指定 v2.19.5
    git clone -b "v2.19.5" --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    if [ "$BUILD_TYPE" != "personal" ]; then
        # 【锁定版本】Passwall Packages 指定 commit 哈希
        git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        pushd package/custom/passwall-packages
        git checkout 1af0a5c4fb3a227201683b64d32f61c65db9be72
        popd

        # 【锁定版本】Passwall 指定 26.10.4-1
        git clone -b "26.10.4-1" --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/custom/passwall-luci
    fi

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

    # 【锁定版本】OpenClash 指定 v0.47.156
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG="v0.47.156"
    echo "正在获取 OpenClash 指定版本 $OPENCLASH_TAG..."
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    git pull --depth 1 origin "$OPENCLASH_TAG"
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

    # 修复 LEDE 源码下 Aurora 主题页脚空括号问题
    echo "修复 LEDE Aurora 主题页脚空括号..."
    find package/custom/luci-theme-aurora -name "footer.ut" -exec sed -i 's/({{ version.distrevision }})/{% if (version.distrevision): %} ({{ version.distrevision }}){% endif %}/g' {} +

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
        "oaf" "kmod-oaf" "appfilter" "luci-app-oaf" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
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

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 等环境组件..."
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        rm -rf feeds/helloworld 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome

    # 【锁定版本】Lucky 指定 v2.19.5
    git clone -b "v2.19.5" --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    if [ "$BUILD_TYPE" != "personal" ]; then
        # 【锁定版本】Passwall Packages 指定 commit 哈希
        git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        pushd package/custom/passwall-packages
        git checkout 1af0a5c4fb3a227201683b64d32f61c65db9be72
        popd

        # 【锁定版本】Passwall 指定 26.10.4-1
        git clone -b "26.10.4-1" --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/custom/passwall-luci
    fi

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

    # 【锁定版本】OpenClash 指定 v0.47.156
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG="v0.47.156"
    echo "正在获取 OpenClash 指定版本 $OPENCLASH_TAG..."
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    git pull --depth 1 origin "$OPENCLASH_TAG"
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

elif [ "$FIRMWARE_TYPE" == "openwrt" ]; then
    echo "====== 开始执行 官方 OpenWrt 专属定制 ======"

    if [ "$BUILD_TYPE" != "personal" ]; then
        echo "【Public 版本专属】：替换高版本 Docker 引擎..."
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
    fi

    openwrt_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-oaf" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
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

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 等环境组件..."
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        rm -rf feeds/helloworld 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman

    # 【锁定版本】Lucky 指定 v2.19.5
    git clone -b "v2.19.5" --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    if [ "$BUILD_TYPE" != "personal" ]; then
        # 【锁定版本】Passwall Packages 指定 commit 哈希
        git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        pushd package/custom/passwall-packages
        git checkout 1af0a5c4fb3a227201683b64d32f61c65db9be72
        popd

        # 【锁定版本】Passwall 指定 26.10.4-1
        git clone -b "26.10.4-1" --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/custom/passwall-luci
    fi

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

    # 【锁定版本】OpenClash 指定 v0.47.156
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG="v0.47.156"
    echo "正在获取 OpenClash 指定版本 $OPENCLASH_TAG..."
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    git pull --depth 1 origin "$OPENCLASH_TAG"
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
    bash add_turboacc.sh --no-sfe

elif [ "$FIRMWARE_TYPE" == "istoreos" ]; then
    echo "====== 开始执行 iStoreOS 专属定制 ======"

    if [ "$BUILD_TYPE" != "personal" ]; then
        if [[ "$SOURCE_BRANCH" == *"25.12"* ]]; then
            IMM_PKG_BRANCH="openwrt-25.12"
        else
            IMM_PKG_BRANCH="master"
        fi

        echo "--- 正在从 immortalwrt/packages 的 $IMM_PKG_BRANCH 分支完整替换 Docker 组件引擎 ---"
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose}
        git clone -b "$IMM_PKG_BRANCH" --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
        cp -r /tmp/imm_packages/utils/{docker,dockerd,containerd,runc,docker-compose} feeds/packages/utils/ || true
        rm -rf /tmp/imm_packages
    fi

    istoreos_conflict_plugins=(
        "adguardhome" "luci-app-adguardhome"
        "luci-app-openclash" "openclash"
        "oaf" "kmod-oaf" "appfilter" "luci-app-oaf" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
        "lucky" "luci-app-lucky"
        "passwall" "luci-app-passwall"
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )

    for plugin in "${istoreos_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin" 2>/dev/null
        rm -rf feeds/luci/*/*/"$plugin" 2>/dev/null
    done

    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null

    if [ "$BUILD_TYPE" == "personal" ]; then
        rm -rf feeds/helloworld 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome

    # 【锁定版本】Lucky 指定 v2.19.5
    git clone -b "v2.19.5" --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"
    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"

    if [ "$BUILD_TYPE" != "personal" ]; then
        # 【锁定版本】Passwall Packages 指定 commit 哈希
        git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        pushd package/custom/passwall-packages
        git checkout 1af0a5c4fb3a227201683b64d32f61c65db9be72
        popd

        # 【锁定版本】Passwall 指定 26.10.4-1
        git clone -b "26.10.4-1" --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/custom/passwall-luci
    fi

    # 【锁定版本】OpenClash 指定 v0.47.156
    OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
    OPENCLASH_TAG="v0.47.156"
    echo "正在获取 OpenClash 指定版本 $OPENCLASH_TAG..."
    mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
    git init
    git remote add origin "$OPENCLASH_REPO"
    git config core.sparseCheckout true
    echo "luci-app-openclash/*" >> .git/info/sparse-checkout
    git pull --depth 1 origin "$OPENCLASH_TAG"
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

    # ====== 5. 仅限 iStoreOS 的专属定制修改 ======
    echo "====== 执行 iStoreOS 专属定制修改 ======"

    # 5.1 修复 Quickstart 家长控制 404 跳转
    echo "修复 Quickstart 家长控制路径..."
    find package/ feeds/ -path "*/luci-static/quickstart/*.js" -exec sed -i 's|admin/services/appfilter|admin/services/oaf|g' {} + 2>/dev/null || true

    # 5.2 植入 SSH 登录 Banner 专属标志
    echo "植入专属 SSH Banner 标志..."
    BANNER_FILE=$(find package/ base-files/ -type f -name "banner" 2>/dev/null | head -n 1)
    if [ -n "$BANNER_FILE" ] && [ -f "$BANNER_FILE" ]; then
        sed -i 's/                                  Powered by OpenWRT/ Compiled by 粉墨悲欢@恩山        Powered by OpenWRT/g' "$BANNER_FILE"
    fi

    # 5.3 修复 iStoreOS 专属菜单在 Aurora 主题下的图标缺失问题 (SVG 遮罩)
    AURORA_CSS="package/custom/luci-theme-aurora/htdocs/luci-static/aurora/css/style.css"
    if [ -f "$AURORA_CSS" ]; then
        echo "注入自定义 CSS 修复 iStoreOS 侧边栏图标..."
        cat << 'EOF' >> "$AURORA_CSS"

/* 首页 (Quickstart) 图标修复 */
a[data-section="quickstart"] .nav-icon {
    -webkit-mask-image: url('../icon/home.svg') !important;
    mask-image: url('../icon/home.svg') !important;
    background-color: currentColor;
}
/* iStore 商店 图标修复 */
a[data-section="istore"] .nav-icon {
    -webkit-mask-image: url('../icon/store.svg') !important;
    mask-image: url('../icon/store.svg') !important;
    background-color: currentColor;
}
/* 网络向导 图标修复 */
a[data-section="netwizard"] .nav-icon {
    -webkit-mask-image: url('../icon/netwizard.svg') !important;
    mask-image: url('../icon/netwizard.svg') !important;
    background-color: currentColor;
}
EOF
    fi

fi
# ==========================================
# 结束 iStoreOS 专属分支
# ==========================================


# ==========================================
# public 公共版：追加拉取 daede 等组件
# ==========================================
if [ "$BUILD_TYPE" == "public" ]; then
    echo "【公共版】：已配置拉取完整编译组件..."
    echo "【清理冲突插件】：删除源码自带的 dae/daed..."
    rm -rf feeds/luci/applications/luci-app-dae
    rm -rf feeds/luci/applications/luci-app-daed
    rm -rf feeds/packages/net/dae
    rm -rf feeds/packages/net/daed

    # 【锁定版本】daede 指定 v2026.09.26
    echo "【拉取原生插件】：正在克隆 kenzok8 维护的原生 daede 源码 (v2026.09.26)..."
    git clone -b "v2026.09.26" --depth 1 "https://github.com/kenzok8/openwrt-daede" "package/custom/daede"
else
    echo "【私有版】：已阻断相关外部代理仓库及组件克隆..."
fi

# ==========================================
# 1.5 OAF 翻译缺失动态修复 (带向前兼容判断)
# ==========================================
echo "====== 检查并修复 OAF 翻译文件 ======"
OAF_PO_FILE=$(find package/custom/ -name "oaf.po" 2>/dev/null | head -n 1)
if [ -n "$OAF_PO_FILE" ] && [ -f "$OAF_PO_FILE" ]; then
    if ! grep -q "/etc/fwx\." "$OAF_PO_FILE"; then
        echo "🔧 发现 OAF 源码翻译未同步，正在动态热修复 /etc/fwx 中文显示..."
        sed -i '/The user.s basic data/ s|/etc/oaf\.|/etc/fwx\.|g' "$OAF_PO_FILE"
        sed -i '/用户的基本数据/ s|/etc/oaf|/etc/fwx|g' "$OAF_PO_FILE"
    else
        echo "🌟 检测到 OAF 原作者已修复该翻译，自动跳过自定义修改。"
    fi
else
    echo "⚠️ 未找到 oaf.po 翻译文件，跳过修复。"
fi


# ==========================================
# 2. 本地化环境与守护脚本注入
# ==========================================
FILES_DIR="package/base-files/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults

# --- 终极防伪暗桩：底层防盗版印记注入 ---
mkdir -p ${FILES_DIR}/etc
echo "Original Creator: 粉墨悲欢@恩山 Forum" > ${FILES_DIR}/etc/.fw_signature
echo 'BUILD_AUTHOR="粉墨悲欢@EnShan"' >> ${FILES_DIR}/etc/os-release
echo "# Firmware compiled and customized by 粉墨悲欢" >> ${FILES_DIR}/etc/profile
# ----------------------------------------

cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/zz_custom_setup
#!/bin/sh

EOF

if [ "$FIRMWARE_TYPE" != "lede-native" ]; then
cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup
# 1. OAF 模块加载 (兼容 F大版本。若是纯原生编译 /root/oaf.ko 不存在，此逻辑自动忽略)
if [ -f /root/oaf.ko ]; then
    KVER=$(uname -r)
    mkdir -p /lib/modules/$KVER
    mv /root/oaf.ko /lib/modules/$KVER/
    depmod -a
    echo "oaf" > /etc/modules.d/99-oaf
    modprobe oaf
fi
EOF
fi

cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 2. 极致洁癖的 sysctl 注入
sed -i '/net.bridge.bridge-nf-call/d' /etc/sysctl.conf
cat << 'SYSCTL_EOF' >> /etc/sysctl.conf

# Network routing & bridge optimization
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-arptables=0
SYSCTL_EOF
sysctl -p
EOF

cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 3. 设置 AdGuardHome 标准路径
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null
EOF

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 4. 彻底清理 LEDE 祖传的跑分计划任务
sed -i '/coremark/d' /etc/crontabs/root 2>/dev/null
/etc/init.d/cron restart 2>/dev/null
EOF
fi

cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 脚本使命完成，自毁
rm -f /etc/uci-defaults/zz_custom_setup
EOF

chmod +x ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

if [ "$FIRMWARE_TYPE" == "lede" ]; then
    cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/98_lede_setup
#!/bin/sh
uci delete uhttpd.main.listen_https 2>/dev/null
uci commit uhttpd 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
rm -f /etc/uci-defaults/98_lede_setup
EOF
fi

# ====== iStoreOS 修改默认原先配置设定 ======
if [ "$FIRMWARE_TYPE" == "istoreos" ]; then
    cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/zzz_istoreos_setup
#!/bin/sh

# 1. 强制设为静态 IP 192.168.1.1，保留 br-lan，并彻底铲除 lan6 接口
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.1.1'
uci set network.lan.netmask='255.255.255.0'
uci delete network.lan.gateway 2>/dev/null
uci delete network.lan.dns 2>/dev/null
uci delete network.lan6 2>/dev/null
uci commit network

# 2. 强制开启 LAN 口的 DHCP 服务器
uci set dhcp.lan.ignore='0' 2>/dev/null
uci set dhcp.lan.start='100' 2>/dev/null
uci set dhcp.lan.limit='150' 2>/dev/null
uci set dhcp.lan.leasetime='12h' 2>/dev/null
uci set dhcp.lan.dhcpv4='server' 2>/dev/null
uci commit dhcp

# 3. 替换 root 密码为 password 的哈希值，跳过 iStoreOS 强制密码向导
sed -i 's/^root:[^:]*:/root:\$1\$V4UetPzk\$CYXluq4wUazHjmCDBCqXF.:/' /etc/shadow

# 4. 强制设置 iStoreOS 默认主题为 Aurora，配置侧边栏并关闭快捷工具栏
uci set luci.main.mediaurlbase='/luci-static/aurora' 2>/dev/null
uci commit luci 2>/dev/null
if [ -f /etc/config/aurora ]; then
    uci set aurora.theme.nav_type='sidebar' 2>/dev/null
    uci set aurora.theme.toolbar_enabled='0' 2>/dev/null
    uci commit aurora 2>/dev/null
fi

# 5. 首次开机自动唤醒 WiFi 并修改参数（后台轮询）
(
    # 循环等待，直到系统内核成功挂载 wlan 物理接口
    for i in $(seq 1 15); do
        if ls /sys/class/net/ | grep -q "^wlan"; then
            break
        fi
        sleep 2
    done

    # 触发系统原生生成默认配置
    wifi config 2>/dev/null

    # 只做最精简的定制：解禁硬件、改名、加密码
    uci set wireless.@wifi-device[0].disabled='0'
    uci delete wireless.@wifi-iface[0].disabled 2>/dev/null
    uci set wireless.@wifi-iface[0].ssid='Phicomm_n1'
    uci set wireless.@wifi-iface[0].encryption='psk2'
    uci set wireless.@wifi-iface[0].key='password'
    uci commit wireless

    # 强制拉起底层物理网卡
    wifi up 2>/dev/null
) &

# 6. 重启网络与无线服务，使 IP、DHCP 和 WiFi 配置立即生效
/etc/init.d/network restart
wifi reload 2>/dev/null

# 7. 脚本执行完毕后自毁 (阅后即焚)
rm -f /etc/uci-defaults/zzz_istoreos_setup
EOF

# ====== 原本的 Personal 版设定 (针对非 iStoreOS) ======
elif [ "$BUILD_TYPE" == "personal" ]; then
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