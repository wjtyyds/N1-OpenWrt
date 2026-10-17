#!/bin/bash
# diy-part2.sh

# ==========================================
# 0. 获取最新或指定日期的 Tag/Hash 克隆函数 (时光机核心)
# ==========================================
clone_time_machine() {
    local repo_url=$1
    local dest_dir=$2
    local target_date=$3
    local use_hash_only=$4

    local repo_path=$(echo "$repo_url" | sed -E 's|https://github.com/([^/]+/[^/.]+)(\.git)?|\1|')
    
    echo "=========================================="
    echo "🚀 启动 [时光机克隆]: 目标目录 -> $dest_dir"
    echo "📅 目标节点: ${target_date:-最新}"
    echo "=========================================="
    
    # 场景 A: 没有指定日期，直接拉取最新 Tag (如果没 Tag 拉 master 最新)
    if [ -z "$target_date" ]; then
        local api_resp=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/$repo_path/releases/latest")
        local latest_tag=$(echo "$api_resp" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

        if [ -n "$latest_tag" ]; then
            echo "✅ [常规拉取] 找到最新 Tag: $latest_tag，正在浅克隆..."
            git clone --branch "$latest_tag" --depth 1 "$repo_url" "package/custom/$dest_dir"
        else
            echo "⚠️ [常规拉取] 未找到 Tag，直接拉取默认分支最新代码..."
            git clone --depth 1 "$repo_url" "package/custom/$dest_dir"
        fi
        return 0
    fi
    
    # 场景 B: 指定了日期，启动严格的回溯机制
    # 1. 尝试寻找日期之前的最新 Release Tag (除非强制只找 Hash)
    if [ "$use_hash_only" != "true" ]; then
        echo "🔍 [时光机] 正在检索 $target_date 之前的最新 Tag..."
        # 遍历前 30 个 releases
        local releases_json=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/$repo_path/releases?per_page=30")
        
        # 提取 published_at 和 tag_name
        local target_tag=""
        
        # jq 脚本：找出第一个 published_at < target_date 的 release 的 tag_name
        target_tag=$(echo "$releases_json" | jq -r --arg date "$target_date" 'map(select(.published_at < $date)) | .[0].tag_name // empty')
        
        if [ -n "$target_tag" ] && [ "$target_tag" != "null" ]; then
            echo "🎉 [时光机] 精准锁定！找到历史 Tag: $target_tag"
            git clone --branch "$target_tag" --depth 1 "$repo_url" "package/custom/$dest_dir"
            return 0
        else
            echo "⚠️ [时光机] 未能在历史中找到合适的 Tag，将降级寻找 Commit Hash..."
        fi
    fi
    
    # 2. 降级或强制寻找日期之前的最后一次 Commit Hash
    echo "🔍 [时光机] 正在检索 $target_date 之前的最后一次提交..."
    
    # 获取默认分支 (通常是 master 或 main)
    local default_branch=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/$repo_path" | jq -r '.default_branch // "master"')
    
    local api_url="https://api.github.com/repos/$repo_path/commits?sha=$default_branch&until=$target_date&per_page=1"
    local commit_hash=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "$api_url" | jq -r '.[0].sha // empty')
    
    if [ -n "$commit_hash" ] && [ "$commit_hash" != "null" ]; then
        echo "🎉 [时光机] 精准锁定！找到历史 Hash: ${commit_hash:0:7}"
        git clone "$repo_url" "package/custom/$dest_dir"
        cd "package/custom/$dest_dir"
        git reset --hard "$commit_hash"
        cd - > /dev/null
    else
        echo "❌ [时光机] 彻底失败！未找到任何历史记录。降级拉取最新代码！"
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
# 1. 统一处理：卸载系统自带的冲突插件 (全局生效)
# ==========================================
echo "====== 统一卸载冲突插件 ======"
conflict_plugins=(
    "adguardhome" "luci-app-adguardhome" "luci-app-openclash" "openclash"
    "oaf" "kmod-oaf" "appfilter" "luci-app-oaf" "luci-app-appfilter" "openappfilter" "luci-app-openappfilter" "open-app-filter"
    "lucky" "luci-app-lucky" "passwall" "luci-app-passwall"
    "hysteria" "sing-box" "xray-core" "xray-plugin" "v2ray-geodata" "v2ray-plugin" "shadowsocks-rust" "shadowsocksr-libev"
    "dae" "daed" "luci-app-dae" "luci-app-daed"
)
for plugin in "${conflict_plugins[@]}"; do
    ./scripts/feeds uninstall "$plugin" || true
    rm -rf feeds/packages/*/*/"$plugin" 2>/dev/null
    rm -rf feeds/luci/*/*/"$plugin" 2>/dev/null
done

# ==========================================
# 2. 统一处理：清理代理底层老旧核心 (全局生效)
# ==========================================
echo "====== 统一清理老旧底层代理核心 ======"
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null

if [ "$BUILD_TYPE" == "personal" ]; then
    echo "【Personal 版本】：物理抹除 Docker 环境与测试仓库..."
    rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose} 2>/dev/null
    rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
    rm -rf feeds/helloworld 2>/dev/null
fi

# ==========================================
# 3. 统一拉取：共用的第三方基础插件库 (全局生效，带时光机)
# ==========================================
echo "====== 统一拉取定制基础插件源码 ======"
# 1. 移除 AdGuardHome 的目标日期变量和 Hash 强制参数，使其跳过时光机直接拉取最新状态
clone_time_machine "https://github.com/wjtyyds/luci-app-adguardhome" "luci-app-adguardhome" ""
clone_time_machine "https://github.com/gdy666/luci-app-lucky" "lucky" "$TARGET_DATE_ISO"
clone_time_machine "https://github.com/destan19/OpenAppFilter" "luci-app-oaf" "$TARGET_DATE_ISO"

# 针对 09.16 专属判断：强制克隆 Aurora 系列的指定版本
echo "👉 [DEBUG-SH] 检查 Aurora 主题拉取策略，TARGET_DATE_ISO: [$TARGET_DATE_ISO]"
if [[ "$TARGET_DATE_ISO" == *"2026-09-16"* ]]; then
    echo "【2026.09.16 专属策略】: 命中，强制拉取 Aurora 指定历史版本..."
    git clone -b v1.4.0 --depth 1 "https://github.com/eamonxg/luci-theme-aurora" "package/custom/luci-theme-aurora"
    git clone -b v1.2.5 --depth 1 "https://github.com/eamonxg/luci-app-aurora-config" "package/custom/luci-app-aurora-config"
else
    echo "✅ [DEBUG-SH] 未命中 09.16 拦截，Aurora 走正常时光机流程。"
    clone_time_machine "https://github.com/eamonxg/luci-theme-aurora" "luci-theme-aurora" "$TARGET_DATE_ISO"
    clone_time_machine "https://github.com/eamonxg/luci-app-aurora-config" "luci-app-aurora-config" "$TARGET_DATE_ISO"
fi

# 统一：OpenClash 浅克隆 (融入时光机逻辑)
OPENCLASH_REPO="https://github.com/vernesong/OpenClash"
echo "正在获取 OpenClash..."
if [ -n "$TARGET_DATE_ISO" ]; then
    OPENCLASH_RELEASES=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/vernesong/OpenClash/releases?per_page=30")
    OPENCLASH_TAG=$(echo "$OPENCLASH_RELEASES" | jq -r --arg date "$TARGET_DATE_ISO" 'map(select(.published_at < $date)) | .[0].tag_name // empty')
else
    OPENCLASH_TAG=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/vernesong/OpenClash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
fi
echo "[时光机] OpenClash 锁定于: ${OPENCLASH_TAG:-最新 master}"

mkdir -p /tmp/OpenClash && cd /tmp/OpenClash
git init; git remote add origin "$OPENCLASH_REPO"; git config core.sparseCheckout true
echo "luci-app-openclash/*" >> .git/info/sparse-checkout
git pull --depth 1 origin "${OPENCLASH_TAG:-master}"
mv luci-app-openclash $GITHUB_WORKSPACE/openwrt/package/custom/
cd $GITHUB_WORKSPACE/openwrt
rm -rf /tmp/OpenClash

# ==========================================
# 4. Public 公共版专属：追加拉取科学代理组件
# ==========================================
if [ "$BUILD_TYPE" == "public" ]; then
    echo "【公共版】：已配置拉取完整代理编译组件..."
    
    # 增加日志
    echo "👉 [DEBUG-SH] 代理组件拉取拦截检查，TARGET_DATE_ISO: [$TARGET_DATE_ISO]"

    if [[ "$TARGET_DATE_ISO" != *"2026-09-09"* ]]; then
        echo "✅ [DEBUG-SH] 未命中 09.09 拦截，拉取 Passwall。"
        clone_time_machine "https://github.com/Openwrt-Passwall/openwrt-passwall-packages" "passwall-packages" "$TARGET_DATE_ISO" "true"
        clone_time_machine "https://github.com/Openwrt-Passwall/openwrt-passwall" "passwall-luci" "$TARGET_DATE_ISO"
    else
        echo "⛔ [DEBUG-SH] 命中 09.09，拦截 Passwall 拉取！"
    fi

    if [[ "$TARGET_DATE_ISO" != *"2026-09-09"* ]] && [[ "$TARGET_DATE_ISO" != *"2026-09-16"* ]]; then
        echo "✅ [DEBUG-SH] 未命中 09.09/09.16 拦截，拉取 Daede。"
        clone_time_machine "https://github.com/kenzok8/openwrt-daede" "daede" "$TARGET_DATE_ISO"
    else
        echo "⛔ [DEBUG-SH] 命中拦截日期，拦截 Daede 拉取！"
    fi
else
    echo "【私有版】：已阻断外部代理套件克隆..."
fi

# ==========================================
# 5. 差异化操作：各分支专有的修补逻辑
# ==========================================
echo "====== 开始各分支的差异化特征修改 ======"

# 替换为 TARGET_DATE_ISO 通配符包含匹配，并增加日志
echo "👉 [DEBUG-SH] 差异化补丁检查，TARGET_DATE_ISO: [$TARGET_DATE_ISO]"
if [[ "$TARGET_DATE_ISO" == *"2026-09-09"* ]]; then
    echo "【2026.09.09 专属补丁】: 命中，开始执行 Dockerman 替换..."
    rm -rf feeds/luci/applications/luci-app-dockerman 2>/dev/null
    rm -rf feeds/luci/libs/luci-lib-docker 2>/dev/null
    clone_time_machine "https://github.com/wjtyyds/luci-app-dockerman" "luci-app-dockerman" "$TARGET_DATE_ISO" "true"
else
    echo "✅ [DEBUG-SH] 未命中 09.09，跳过 Dockerman 替换。"
fi

if [[ "$FIRMWARE_TYPE" == lede* ]]; then
    if [ "$FIRMWARE_TYPE" == "lede-native" ]; then
        sed -i 's/KERNEL_PATCHVER:=6.18/KERNEL_PATCHVER:=6.6/g' target/linux/amlogic/Makefile
    fi
    # 修复 LEDE Aurora 主题页脚
    find package/custom/luci-theme-aurora -name "footer.ut" -exec sed -i 's/({{ version.distrevision }})/{% if (version.distrevision): %} ({{ version.distrevision }}){% endif %}/g' {} +

elif [ "$FIRMWARE_TYPE" == "immortalwrt" ]; then
    if [ "$SOURCE_BRANCH" == "v25.12.1" ]; then
        rm -rf feeds/packages/lang/rust
        git clone --depth 1 https://github.com/openwrt/packages.git /tmp/openwrt_packages
        cp -r /tmp/openwrt_packages/lang/rust feeds/packages/lang/
        rm -rf /tmp/openwrt_packages
    fi

elif [ "$FIRMWARE_TYPE" == "openwrt" ] || [ "$FIRMWARE_TYPE" == "istoreos" ]; then
    if [ "$BUILD_TYPE" != "personal" ]; then
        # OpenWrt 和 iStoreOS 共同的高版本 Docker 替换逻辑
        if [[ "$SOURCE_BRANCH" =~ ^v([0-9]+\.[0-9]+) ]] || [[ "$SOURCE_BRANCH" == *"25.12"* ]]; then
            IMM_PKG_BRANCH="openwrt-${BASH_REMATCH[1]:-25.12}"
        else
            IMM_PKG_BRANCH="master"
        fi
        rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc,docker-compose}
        git clone -b "$IMM_PKG_BRANCH" --depth 1 https://github.com/immortalwrt/packages.git /tmp/imm_packages
        cp -r /tmp/imm_packages/utils/{docker,dockerd,containerd,runc,docker-compose} feeds/packages/utils/ || true
        rm -rf /tmp/imm_packages
    fi

    # 分支独有逻辑
    if [ "$FIRMWARE_TYPE" == "openwrt" ]; then
        git clone --depth 1 https://github.com/lisaac/luci-app-diskman package/custom/luci-app-diskman
        curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh | bash -s -- --no-sfe
    elif [ "$FIRMWARE_TYPE" == "istoreos" ]; then
        find package/ feeds/ -path "*/luci-static/quickstart/*.js" -exec sed -i 's|admin/services/appfilter|admin/services/oaf|g' {} + 2>/dev/null || true
        BANNER_FILE=$(find package/ base-files/ -type f -name "banner" 2>/dev/null | head -n 1)
        if [ -n "$BANNER_FILE" ]; then
            sed -i 's/                                  Powered by OpenWRT/ Compiled by 粉墨悲欢@恩山        Powered by OpenWRT/g' "$BANNER_FILE"
        fi
    fi
fi

# ==========================================
# 6. OAF 翻译缺失动态修复 (带向前兼容判断)
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
# 7. 本地化环境与守护脚本注入
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

# 第二部分：Sysctl 注入 (对所有固件生效)
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

# 第三部分：追加剩余公共逻辑与阅后即焚
cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 3. 设置 AdGuardHome 标准路径
uci set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null
uci set AdGuardHome.AdGuardHome.workdir='/usr/bin/AdGuardHome' 2>/dev/null
uci commit AdGuardHome 2>/dev/null
EOF

# ================= 专属修正：只给 LEDE 写入清理跑分任务 =================
if [[ "$FIRMWARE_TYPE" == lede* ]]; then
cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

# 4. 彻底清理 LEDE 祖传的跑分计划任务
sed -i '/coremark/d' /etc/crontabs/root 2>/dev/null
/etc/init.d/cron restart 2>/dev/null
EOF
fi
# =====================================================================

cat << 'EOF' >> ${FILES_DIR}/etc/uci-defaults/zz_custom_setup

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
    # 💡 命名为 zzz_istoreos_setup，保证全系统绝对最后一个执行
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

    # 触发系统原生生成默认配置（不加 rm -f，绝不破坏原有默认参数）
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
