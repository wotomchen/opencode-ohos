# OpenCode for HarmonyOS

OpenCode AI 编程助手的鸿蒙（HarmonyOS）自包含运行包。

内含 Node.js 22 arm64 运行时 + OpenCode 全部依赖，**无需预装 Node.js**，解压即用。

---

## 目录结构

```
~/.opencode/
├── bin/opencode          # 启动脚本
├── node/node             # Node.js 22 arm64（86 MB）
├── index.mjs             # 主入口
├── bundle.mjs            # 主 bundle
├── package.json
├── node_modules/         # 所有外部依赖
├── web-ui/               # Web 管理界面
├── cli/cmd/tui/worker.mjs
├── tui/worker.mjs
├── install-opencode-ohos.sh       # tar.gz 安装脚本
├── install-opencode-ohos-git.sh   # Git 安装脚本
└── README.md
```

---

## 安装方法

### 方法一：从 tar.gz 安装（推荐）

```sh
curl -fsSL https://gitcode.com/wotomchen/opencode-ohos/releases/download/OpenCode-1.14.33-ohos-v0/install-opencode-ohos.sh | sh
```

### 方法二：从 Git 仓库克隆

```sh
curl -fsSL https://gitcode.com/wotomchen/opencode-ohos/releases/download/OpenCode-1.14.33-ohos-v0/install-opencode-ohos-git.sh | sh
```

保留 `.git` 以便后续 `git pull` 更新：

```sh
KEEP_GIT_DIR=true sh -c "$(curl -fsSL https://gitcode.com/wotomchen/opencode-ohos/releases/download/OpenCode-1.14.33-ohos-v0/install-opencode-ohos-git.sh)"
```

安装脚本会自动执行以下操作：
1. ✅ 下载/克隆运行时文件到 `~/.opencode/`
2. ✅ 设置可执行权限
3. 🔑 查找 `binary-sign-tool` 并对所有原生 ELF 二进制文件进行**自签名**
4. ❌ 若未找到签名工具，会打印手动签名指引

---

## 启动

```sh
~/.opencode/bin/opencode
```

或添加到 PATH：

```sh
export PATH="$PATH:$HOME/.opencode/bin"
opencode
```

首次启动需要登录或配置 API Key，参考 [OpenCode 官方文档](https://opencode.ai/docs)。

---

## 当前测试范围

> 当前**仅在 HarmonyOS 上测试了以下两种模式**：

| 模式 | 状态 |
|---|---|
| **TUI**（终端交互界面） | ✅ 已验证 |
| **Web**（Web 管理界面） | ✅ 已验证 |

其他功能（如 VS Code 扩展、桌面应用等）尚未在鸿蒙上验证。

---

## 签名说明

> HarmonyOS 要求所有 ELF 二进制文件签名后才能运行。

**构建机**上已用 `binary-sign-tool sign -selfSign "1"` 签过名，但**自签名证书绑定设备硬件**，换一台机器必须重新签名。

安装脚本会自动查找 `binary-sign-tool` 并签名以下 7 个文件：

| 文件 | 用途 |
|---|---|
| `node/node` | Node.js 运行时 |
| `node_modules/better-sqlite3/build/Release/better_sqlite3.node` | SQLite 数据库引擎 |
| `node_modules/@lydell/node-pty-openharmony-arm64/prebuilds/openharmony-arm64/pty.node` | 伪终端 |
| `node_modules/@lydell/node-pty-openharmony-arm64/prebuilds/openharmony-arm64/preload_tty.so` | 终端预加载库 |
| `node_modules/@opentui/core-openharmony-arm64/prebuilds/openharmony-arm64/libopentui.so` | TUI 渲染引擎 |
| `node_modules/@parcel/watcher-openharmony-arm64/watcher.node` | 文件变更监听 |
| `node_modules/@koromix/koffi-openharmony-arm64/ohos_arm64/koffi.node` | FFI 调用库 |

如需手动签名（脚本未找到 `binary-sign-tool` 时）：

```sh
# 逐个文件签名（需先找到 binary-sign-tool）
BIN_TOOL="$HOME/.local/bin/binary-sign-tool"  # 常见路径
# BIN_TOOL="/usr/local/bin/binary-sign-tool"  # 备选路径

sign_file() {
  f="$1"
  if [ ! -f "$f" ] || ! file "$f" | grep -q "ELF"; then
    echo "not an ELF binary: $f"
    return 1
  fi
  mv "$f" "${f}-unsigned" && \
  "$BIN_TOOL" sign -inFile "${f}-unsigned" -outFile "$f" -selfSign "1" && \
  chmod +x "$f"
}

sign_file ~/.opencode/node/node
sign_file ~/.opencode/node_modules/better-sqlite3/build/Release/better_sqlite3.node
sign_file ~/.opencode/node_modules/@lydell/node-pty-openharmony-arm64/prebuilds/openharmony-arm64/pty.node
sign_file ~/.opencode/node_modules/@lydell/node-pty-openharmony-arm64/prebuilds/openharmony-arm64/preload_tty.so
sign_file ~/.opencode/node_modules/@opentui/core-openharmony-arm64/prebuilds/openharmony-arm64/libopentui.so
sign_file ~/.opencode/node_modules/@parcel/watcher-openharmony-arm64/watcher.node
sign_file ~/.opencode/node_modules/@koromix/koffi-openharmony-arm64/ohos_arm64/koffi.node
```

---

## 版本

当前版本: **1.14.33-ohos**

---

## 链接

- OpenCode 官方: [https://opencode.ai](https://opencode.ai)
- 鸿蒙发布包: [https://gitcode.com/wotomchen/opencode-ohos](https://gitcode.com/wotomchen/opencode-ohos)
- OpenCode 源码: [https://github.com/anomalyco/opencode](https://github.com/anomalyco/opencode)
