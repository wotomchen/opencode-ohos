#!/bin/sh
# OpenCode for HarmonyOS 一键安装脚本
#
# 用法:
#   curl -fsSL https://gitcode.com/wotomchen/opencode-ohos/releases/download/OpenCode-1.14.33-ohos-v0/install-opencode-ohos.sh | sh
#
# 或:
#   wget -qO- https://gitcode.com/wotomchen/opencode-ohos/releases/download/OpenCode-1.14.33-ohos-v0/install-opencode-ohos.sh | sh
#
# 环境变量:
#   OPENCODE_VERSION=1.14.33   # 指定版本（默认 1.14.33）
#   OPENCODE_MIRROR=...        # 自定义下载地址（默认 GitCode Releases）
#   OPENCODE_INSTALL_DIR=...   # 安装目录（默认 $HOME/.opencode）

set -e

# 默认配置
VERSION="${OPENCODE_VERSION:-1.14.33}"
BASE_URL="${OPENCODE_MIRROR:-https://gitcode.com/wotomchen/opencode-ohos/releases/download}"
INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode}"
TMPDIR="${TMPDIR:-$HOME/tmp}"

# 检测架构
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Error: unsupported architecture: $ARCH (only arm64)" >&2; exit 1 ;;
esac

# 拼接下载 URL
DOWNLOAD_URL="${BASE_URL}/OpenCode-${VERSION}-ohos-v0/opencode-ohos-${VERSION}-${ARCH}.tar.gz"

echo "OpenCode HarmonyOS 安装器"
echo "  版本: $VERSION"
echo "  架构: $ARCH"
echo "  目标: $INSTALL_DIR"
echo ""

# 创建临时目录
PKG_TMP="$TMPDIR/opencode-install-$$"
mkdir -p "$PKG_TMP"

# 下载
echo "下载中..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$DOWNLOAD_URL" -o "$PKG_TMP/package.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$DOWNLOAD_URL" -O "$PKG_TMP/package.tar.gz"
else
  echo "Error: need curl or wget" >&2
  exit 1
fi

# 解压
echo "解压中..."
mkdir -p "$INSTALL_DIR"
tar xzf "$PKG_TMP/package.tar.gz" -C "$INSTALL_DIR" --strip-components=1

# 确保可执行
chmod +x "$INSTALL_DIR/bin/opencode" "$INSTALL_DIR/node/node" 2>/dev/null || true

# ── 签名原生二进制 ─────────────────────────────────────────
# 不同 HarmonyOS 设备的自签名证书不同，构建机上签过的文件
# 在目标机上无法运行。解压后必须重新签名。
#
# 签名步骤：
#   1. file → 确认是 ELF 文件
#   2. mv   → 备份为 ${file}-unsigned
#   3. binary-sign-tool sign -inFile ... -outFile ... -selfSign "1"
#   4. chmod +x

echo ""
echo "════════════════════════════════════════════"
echo "  🔑 签名原生二进制"
echo "════════════════════════════════════════════"

# 查找 binary-sign-tool
SIGN_TOOL=""
if command -v binary-sign-tool >/dev/null 2>&1; then
  SIGN_TOOL="binary-sign-tool"
elif [ -x "$HOME/.local/bin/binary-sign-tool" ]; then
  SIGN_TOOL="$HOME/.local/bin/binary-sign-tool"
elif [ -x /usr/local/bin/binary-sign-tool ]; then
  SIGN_TOOL="/usr/local/bin/binary-sign-tool"
fi

# 需要签名的 ELF 文件列表（相对于 INSTALL_DIR）
NATIVE_FILES="node/node
node_modules/better-sqlite3/build/Release/better_sqlite3.node
node_modules/@lydell/node-pty-openharmony-arm64/prebuilds/openharmony-arm64/pty.node
node_modules/@lydell/node-pty-openharmony-arm64/prebuilds/openharmony-arm64/preload_tty.so
node_modules/@opentui/core-openharmony-arm64/prebuilds/openharmony-arm64/libopentui.so
node_modules/@parcel/watcher-openharmony-arm64/watcher.node
node_modules/@koromix/koffi-openharmony-arm64/ohos_arm64/koffi.node
"

if [ -z "$SIGN_TOOL" ]; then
  echo "  ⚠ 未找到 binary-sign-tool，跳过自动签名"
  echo ""
  echo "  安装后请手动运行以下命令签名："
  echo "  (需先 source ~/.zshrc 加载 sign 命令)"
  echo ""
  for relpath in $NATIVE_FILES; do
    [ -z "$relpath" ] && continue
    [ -f "$INSTALL_DIR/$relpath" ] || continue
    echo "    sign \"$INSTALL_DIR/$relpath\""
  done
  echo ""
else
  echo "  签名工具: $SIGN_TOOL"
  echo ""

  # 临时关闭 set -e，单个文件签名失败不阻断整体流程
  set +e

  SIGN_COUNT=0
  FILE_COUNT=0
  for relpath in $NATIVE_FILES; do
    [ -z "$relpath" ] && continue
    f="$INSTALL_DIR/$relpath"
    FILE_COUNT=$((FILE_COUNT + 1))

    echo "──────────────────────────────────────────"
    echo "  文件 ${FILE_COUNT}: ${relpath}"

    # ── 检查文件是否存在 ──
    if [ ! -f "$f" ]; then
      echo "  ⚠ 文件不存在，跳过"
      continue
    fi

    # ── Step 1: file 确认 ELF ──
    echo "  [1/4] 检查文件类型"
    echo "        $ file \"${relpath}\""
    FILE_OUTPUT="$(file "$f" 2>&1)"
    echo "        → ${FILE_OUTPUT}"
    case "$FILE_OUTPUT" in
      *ELF*)
        echo "        ✓ 确认是 ELF 二进制"
        ;;
      *)
        echo "        ⚠ 不是 ELF 文件，跳过"
        continue
        ;;
    esac

    # ── Step 2: mv 备份 ──
    echo "  [2/4] 备份原始文件"
    echo "        $ mv \"${relpath}\" \"${relpath}-unsigned\""
    if mv "$f" "${f}-unsigned"; then
      echo "        ✓ 已备份至 ${relpath}-unsigned"
    else
      echo "        ✗ 备份失败，跳过该文件"
      continue
    fi

    # ── Step 3: binary-sign-tool 签名 ──
    echo "  [3/4] 签名"
    echo "        $ ${SIGN_TOOL} sign \\"
    echo "            -inFile \"${relpath}-unsigned\" \\"
    echo "            -outFile \"${relpath}\" \\"
    echo "            -selfSign \"1\""
    if "${SIGN_TOOL}" sign -inFile "${f}-unsigned" -outFile "${f}" -selfSign "1"; then
      echo "        ✓ 签名成功"
    else
      echo "        ✗ 签名失败，恢复原始文件"
      mv "${f}-unsigned" "${f}"
      continue
    fi

    # ── Step 4: chmod +x ──
    echo "  [4/4] 恢复可执行权限"
    echo "        $ chmod +x \"${relpath}\""
    chmod +x "${f}"
    echo "        ✓ 可执行权限已设置"

    SIGN_COUNT=$((SIGN_COUNT + 1))
    echo "  ✅ 签名完成: ${relpath}"
  done

  # 恢复 set -e
  set -e

  echo "──────────────────────────────────────────"
  echo "  ✅ 签名汇总: ${SIGN_COUNT}/${FILE_COUNT} 个文件签名成功"
fi

# 清理
rm -rf "$PKG_TMP"

echo ""
echo "✅ 安装完成！"
echo ""
echo "  运行: $INSTALL_DIR/bin/opencode"
echo ""
echo "  或添加到 PATH:"
echo "    export PATH=\"\$PATH:$INSTALL_DIR/bin\""
