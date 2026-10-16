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
        # 把 hysteria 等核心组件加进来，让系统彻底 uninstall 解除软链接
        "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    )
    for plugin in "${lede_conflict_plugins[@]}"; do
        ./scripts/feeds uninstall "$plugin" || true
        rm -rf feeds/packages/*/*/"$plugin"
        rm -rf feeds/luci/*/*/"$plugin"
    done

    # 💡 核心修复：为 Public 版的 passwall 让路，强制删除系统自带的老旧核心
    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 与 剩余代理组件..."
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        rm -rf feeds/helloworld 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    if [ "$BUILD_TYPE" != "personal" ]; then
        git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"
    fi

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

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
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi
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

    # 💡 核心修复：清理官方包中干涉 Passwall 核心的旧版组件
    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
    rm -rf feeds/luci/applications/luci-app-passwall

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：执行终极物理阉割，抹除 Docker 等环境组件..."
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
        rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
        rm -rf feeds/helloworld 2>/dev/null
    fi

    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    if [ "$BUILD_TYPE" != "personal" ]; then
        git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"
    fi

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

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
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi
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

    # 💡 核心修复：清理官方包中干涉 Passwall 核心的旧版组件
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
    git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky

    if [ "$BUILD_TYPE" != "personal" ]; then
        git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"
    fi

    clone_latest_tag "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora"
    clone_latest_tag "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config"
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

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
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi
    mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
    cd $GITHUB_WORKSPACE/openwrt
    rm -rf /tmp/OpenClash

    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
    bash add_turboacc.sh --no-sfe

elif [ "$FIRMWARE_TYPE" == "istoreos" ]; then
    echo "====== 开始执行 iStoreOS 专属定制 ======"

    if [ "$BUILD_TYPE" != "personal" ]; then
        echo "【Public 版本专属】：为 iStoreOS 替换高版本 Docker 引擎..."

        # 针对 istoreos-25.12 分支做专门判断
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

    # 1. 强力卸载 iStoreOS 自带的冲突插件与相关依赖
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

    # 2. 深度清理 Passwall 相关的旧版底层核心 (防止编译时依赖冲突)
    rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null

    if [ "$BUILD_TYPE" == "personal" ]; then
        echo "【Personal 版本】：物理抹除多余代理仓库..."
        rm -rf feeds/helloworld 2>/dev/null
    fi

    # 3. 拉取你指定的定制源
    git clone --depth 1 https://github.com/wjtyyds/luci-app-adguardhome.git package/custom/luci-app-adguardhome
    git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky
    clone_latest_tag "https://github.com/destan19/OpenAppFilter" "luci-app-oaf"

    if [ "$BUILD_TYPE" != "personal" ]; then
        git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/custom/passwall-packages
        clone_latest_tag "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci"
    fi

    # 4. OpenClash 浅克隆 (精准拉取核心目录)
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
        git pull --depth 1 origin "$OPENCLASH_TAG"
    else
        git pull --depth 1 origin master
    fi

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
        # 如果是替换原始系统里的，确保不带脏数据
        # 1. 恢复原始 banner (如果从别的分支过来，可能没改，不破坏结构直接改内容)
        # 2. 将“Powered by”这行前面的空白替换为专属标志
        sed -i 's/                                  Powered by OpenWRT/ Compiled by 粉墨悲欢@恩山        Powered by OpenWRT/g' "$BANNER_FILE"
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

    echo "【拉取原生插件】：正在克隆 kenzok8 维护的原生 daede 源码..."
    clone_latest_tag "https://github.com/kenzok8/openwrt-daede" "daede"
else
    echo "【私有版】：已阻断相关外部代理仓库及组件克隆..."
fi

# ==========================================
# 1.5 OAF 翻译缺失动态修复 (带向前兼容判断)
# ==========================================
echo "====== 检查并修复 OAF 翻译文件 ======"
# 全局查找 oaf.po 文件路径
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

# 💡 命名为 zz_custom_setup 保证全系统最后一个执行，绝对秒杀 LEDE 祖传跑分
# 第一部分：写入公共开头和 OAF 模块逻辑
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/zz_custom_setup
#!/bin/sh

EOF

# 针对 lede-native 排除手动加载 OAF 的步骤
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

# 第二部分：Sysctl 注入 (明确排除 iStoreOS)
if [ "$FIRMWARE_TYPE" != "istoreos" ]; then
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
fi

# 第三部分：追加剩余公共逻辑与阅后即焚
cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 3. 设置 AdGuardHome 标准路径
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null

# 4. 彻底清理 LEDE 祖传的跑分计划任务
sed -i '/coremark/d' /etc/crontabs/root 2>/dev/null
/etc/init.d/cron restart 2>/dev/null

# 脚本使命完成，自毁
rm -f /etc/uci-defaults/zz_custom_setup
EOF

# 赋予执行权限
chmod +x ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 【核心修正】：废除 lede-native 针对 443 端口的补丁
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
    cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/97_personal_setup
#!/bin/sh

# 1. 强制 LAN 口为静态 IP，指定 192.168.1.1，方便网线直连电脑进后台
uci delete network.lan.type 2>/dev/null
uci set network.lan.device='eth0'
uci set network.lan.ifname='eth0'
uci set network.lan.proto='static'
uci delete network.lan.ipaddr
uci add_list network.lan.ipaddr='192.168.1.1/24'
uci delete network.lan.gateway 2>/dev/null
uci delete network.lan.dns 2>/dev/null
uci commit network

# 2. 替换 root 密码为 password 的哈希值，跳过 iStoreOS 强制密码向导
sed -i 's/^root:[^:]*:/root:\$1\$V4UetPzk\$CYXluq4wUazHjmCDBCqXF.:/' /etc/shadow

# 3. 脚本执行完毕后自毁 (阅后即焚)
rm -f /etc/uci-defaults/97_personal_setup
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