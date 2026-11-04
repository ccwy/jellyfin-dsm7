# Jellyfin for Synology DSM 7.2+

自动将 [Jellyfin](https://jellyfin.org) 官方 Linux 二进制打包为 Synology DSM 7.2+ 的 `.spk` 套件。

## 特性

- 🔄 **每日自动构建** — GitHub Actions 每天 10:00 (北京时间) 自动检测 Jellyfin 新版本并打包发布
- 🖱️ **手动触发** — 支持指定版本号和架构手动构建
- 📦 **开箱即用** — 包含 ffmpeg、共享库、字体等全部依赖，无需额外配置
- 🏗️ **双架构支持** — 支持 x64 (Intel/AMD) 和 arm64v8 (ARM)

## 下载

前往 [Releases](../../releases) 页面，选择对应你 NAS 架构的 `.spk` 文件：

| 架构 | 文件名 | 适用型号 |
|------|--------|---------|
| x64 | `jellyfin_v*.-x64_DSM7.2+.spk` | Intel/AMD 处理器的 NAS (大部分 DS+ 系列) |
| arm64v8 | `jellyfin_v*.-arm64v8_DSM7.2+.spk` | ARM 64 位处理器的 NAS |

## 安装

1. 下载对应架构的 `.spk` 文件
2. 登录 DSM → **套件中心** → **手动安装** → 选择 `.spk` 文件
3. 按提示完成安装
4. 安装完成后访问 `http://你的NAS_IP:8096` 进行初始设置

## 手动触发构建

在 GitHub 仓库页面 → **Actions** → **Build Jellyfin SPK** → **Run workflow**：

- **version**: 留空则自动检测最新版本，或指定版本号 (如 `10.10.7`)
- **arch**: 选择 `amd64`、`arm64` 或 `both`

## 项目结构

```
jellyfin-dsm7/
├── .github/workflows/
│   └── build.yml              # GitHub Actions 工作流
├── scripts/
│   └── build_spk.sh           # 打包脚本
├── templates/
│   ├── INFO.template          # SPK 元信息模板
│   ├── PACKAGE_ICON.PNG       # 套件图标 72x72
│   ├── PACKAGE_ICON_256.PNG   # 套件图标 256x256
│   ├── conf/
│   │   ├── privilege          # 权限配置 (运行用户/组)
│   │   └── resource           # 资源配置 (视频驱动/共享目录)
│   ├── scripts/               # 安装/卸载/升级脚本
│   │   ├── installer          # 核心安装逻辑
│   │   ├── service-setup      # 服务配置
│   │   ├── start-stop-status  # 服务启停
│   │   └── ...
│   ├── WIZARD_UIFILES/
│   │   └── uninstall_uifile   # 卸载向导界面
│   ├── ui/
│   │   ├── config             # DSM 应用入口配置
│   │   └── images/            # 应用图标
│   └── data/                  # 预置数据 (媒体库配置)
└── README.md
```

## 打包原理

1. 从 [repo.jellyfin.org](https://repo.jellyfin.org) 下载 Jellyfin 官方 Linux 二进制包
2. 从参考 SPK (v10.10.7) 提取辅助文件：ffmpeg、共享库 (.so)、字体、配置等
3. 用新的 Jellyfin 二进制替换 `service/bin/` 和 `service/web/`
4. 组装 `package.tgz`，计算 MD5 校验和
5. 生成 INFO 文件，打包为 `.spk` (tar 归档)

## 致谢

- [Jellyfin Project](https://jellyfin.org) — 开源媒体服务器
- 参考套件基于社区维护的 DSM 7.2+ 打包方案

## 许可证

GPL-2.0 — 与 Jellyfin 项目一致
