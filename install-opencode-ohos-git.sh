#!/bin/sh
# OpenCode for HarmonyOS — Git 安装脚本
#
# 从 GitCode 仓库克隆 OpenCode + Node.js 自包含运行时到本地。
#
# 用法:
#   curl -fsSL https://gitcode.com/wotomchen/opencode-ohos/releases/download/OpenCode-1.14.33-ohos-v0/install-opencode-ohos-git.sh | sh
#
# 环境变量:
#   GIT_REPO_URL=https://gitcode.com/wotomchen/opencode-ohos.git  # 仓库地址（默认）
#   GIT_BRANCH=main                                                # 分支（默认 main）
#   OPENCODE_INSTALL_DIR=...                                       # 安装目录（默认 $HOME/.opencode）
#   KEEP_GIT_DIR=true                                              # 保留 .git 以便后续 git pull 更新

set -e

# 默认配置
GIT_REPO_URL="${GIT_REPO_URL:-https://gitcode.com/wotomchen/opencode-ohos.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"
INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode}"
KEEP_GIT_DIR="${KEEP_GIT_DIR:-false}"
TMPDIR="${TMPDIR:-$HOME/tmp}"

echo "OpenCode HarmonyOS 安装器 (Git)"
echo "  仓库: $GIT_REPO_URL"
echo "  分支: $GIT_BRANCH"
echo "  目标: $INSTALL_DIR"
echo ""

# 检查 git
if ! command -v git >/dev/null 2>&1; then
  echo "Error: 需要 git，但未找到" >&2
  exit 1
fi

# 创建临时目录
CLONE_DIR="$TMPDIR/opencode-clone-$$"
echo "克隆中... 临时目录: $CLONE_DIR"
echo ""

# 浅克隆（只拉最新版本，减少下载量）
git clone --depth 1 --branch "$GIT_BRANCH" "$GIT_REPO_URL" "$CLONE_DIR"

# 创建安装目录
mkdir -p "$INSTALL_DIR"

# 复制内容到安装目录
echo ""
echo "复制到 $INSTALL_DIR..."
cp -r "$CLONE_DIR"/. "$INSTALL_DIR"/
if [ "$KEEP_GIT_DIR" != "true" ]; then
  rm -rf "$INSTALL_DIR/.git"
fi

# 清理临时目录
echo "清理临时目录..."
rm -rf "$CLONE_DIR"

# 确保可执行
chmod +x "$INSTALL_DIR/bin/opencode" "$INSTALL_DIR/node/node" 2>/dev/null || true

# ── 签名原生二进制 ─────────────────────────────────────────
# 不同 HarmonyOS 设备的自签名证书不同，构建机上签过的文件
# 在目标机上无法运行。克隆后必须重新签名。
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

# 如果保留了 .git，提示后续可 git pull 更新
if [ "$KEEP_GIT_DIR" = "true" ]; then
  echo ""
  echo "  📦 .git 已保留，后续可用以下命令更新："
  echo "    cd $INSTALL_DIR && git pull"
fi

echo ""
echo "✅ 安装完成！"
echo ""
echo "  运行: $INSTALL_DIR/bin/opencode"
echo ""
echo "  或添加到 PATH:"
echo "    export PATH=\"\$PATH:$INSTALL_DIR/bin\""
