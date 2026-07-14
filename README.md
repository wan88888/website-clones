# website-clones

一个用于批量克隆网站的工作区。核心思路是**生成器（Generator）模型**：把
[AI Website Cloner Template](https://github.com/JCodesMore/ai-website-cloner-template)
当作生成器，`sites/` 存放生成出来的网站项目。工作区根目录自身也是一个 git 仓库，
只跟踪脚本与 Cursor 配置，不跟踪模板与各站点（它们各自有独立仓库）。

## 冷启动

```bash
# 1. Node 24+（nvm / fnm / asdf 任选）
nvm install 24 && nvm use   # 或: fnm use / asdf shell nodejs 24

# 2. 首次拉取生成器（之后用 update-template 更新）
scripts/bootstrap-template.sh
# 等价: npm run bootstrap

# 3. 建站并克隆（见下文）
scripts/new-site.sh acme https://acme.example.com
```

`update-template.sh` 在生成器不存在时也会自动 bootstrap。

## 目录结构

```
website-clones/                   # 工作区 git（脚本 + .cursor + README + package.json）
├── ai-website-cloner-template/   # 生成器（独立 git）：追踪官方更新，请勿修改
├── sites/                        # 各站点（各自独立 git）：网站项目代码
├── scripts/                      # 自动化脚本
├── .cursor/                      # Cursor：/clone-website、规则、Playwright MCP
├── .nvmrc                        # nvm/fnm/asdf：默认切到 Node 24
├── package.json                  # engines: node >=24（声明最低版本）
├── sites.example.txt
└── README.md
```

### 生成器 vs 站点

- **生成器（`ai-website-cloner-template/`）** 只负责“生产”：AI 工具链、克隆技能源、
  Next.js 脚手架。官方镜像，**保持不修改**。
- **站点（`sites/<名称>/`）** 是“产品”：可独立构建/运行/部署的 Next.js 项目。
  - **默认有：** `src/`、`public/`、构建配置、`.nvmrc`
  - **克隆过程可有：** `docs/research/`、`docs/design-references/`、临时下载脚本
  - **可选（`--with-docker`）：** `Dockerfile*`、`docker-compose.yml`、`.dockerignore`
  - **不可以有：** `.claude/`、`.cursor/`、`AGENTS.md`、官方 sync 脚本等生成器工具链

> 每个站点有 `.generator-version`，记录来自生成器的哪个 commit。

## Node.js 版本

- **要求：Node.js 24+**（与官方模板 `engines` 一致）
- 两处声明分工不同，都需要保留：
  - **`package.json` `engines`**：声明最低版本（`>=24`）；npm 等可校验，**不会**自动切版本
  - **`.nvmrc`**：给 nvm / fnm / asdf 等用，进目录时切到具体版本（`24`）
- 工作区根目录与各站点脚手架都带 `.nvmrc`
- 脚本在版本偏低时会按顺序尝试：**nvm → fnm → asdf**

```bash
nvm install 24 && nvm use          # 读取 .nvmrc
# 或: fnm install && fnm use
# 或: asdf install nodejs 24.x.x && asdf shell nodejs 24.x.x
node -v                            # 应显示 v24.x
```

## 在 Cursor 中克隆网站

`/clone-website` 由两部分合成（见下文「Cursor 命令同步」）。
浏览器自动化使用钉死版本的 Playwright MCP：
改 `.cursor/playwright-mcp.version`，再跑 `scripts/build-clone-command.sh`
（会同步写入 `.cursor/mcp.json`）。

**首次使用：** Cursor 设置 → MCP → 启用项目级 `playwright`。

### 第 1 步：创建站点

```bash
scripts/new-site.sh acme https://acme.example.com
# 若需要 Docker 部署文件：
scripts/new-site.sh acme https://acme.example.com --with-docker
```

默认**不**安装依赖。需要开发时再：

```bash
scripts/install-deps.sh acme
```

### 第 2 步：在站点里运行克隆

```bash
cd sites/acme
```

在 Cursor 中执行：`/clone-website https://acme.example.com`

### 第 3 步：预览 / 看进度

```bash
npm run dev
scripts/site-status.sh
```

## 批量克隆

```bash
cp sites.example.txt sites.txt
scripts/batch-clone.sh                 # 建目录 + 打印后续 /clone-website 清单
scripts/batch-clone.sh --with-docker   # 同时附带 Docker 文件
scripts/site-status.sh
```

## Cursor 命令同步方式

| 文件 | 角色 |
| ---- | ---- |
| `.cursor/commands/clone-website.override.md` | **可编辑**：本工作区生成器模型覆盖规则 |
| `.cursor/commands/clone-website.upstream.md` | 上游技能快照（由更新脚本刷新） |
| `.cursor/commands/clone-website.md` | **自动生成**：override + upstream，勿手改 |

```bash
scripts/bootstrap-template.sh       # 首次克隆生成器（幂等）
scripts/update-template.sh          # 拉生成器 → 刷新 upstream → 重建 clone-website.md + 同步 MCP
scripts/build-clone-command.sh      # 仅重建命令 + 同步 Playwright pin（改完 override / 升 pin 后跑）
scripts/check.sh                    # shellcheck + pin / clone-website.md 一致性（需 brew install shellcheck）
```

`update-template.sh` **不会**覆盖 `clone-website.override.md`，因此本地定制在官方更新后仍然保留。

## 依赖与磁盘 / 同步更新

```bash
scripts/install-deps.sh [站点...] [--ci] [--force]
scripts/prune-deps.sh [站点...] [--next] [--dry-run]

scripts/update-template.sh
scripts/update-sites.sh                 # 受管构建配置
scripts/update-sites.sh --deps          # + package.json / lockfile
scripts/update-sites.sh --docker        # 强制同步 Docker 文件
scripts/update-sites.sh --install       # 同步 deps 后安装
```

已有 `Dockerfile` 的站点会在常规 `update-sites` 时自动同步 Docker 相关文件；没有 Docker 的纯网站站点不会被塞入这些运维文件。

## 法律与使用边界

本工作区与上游模板一样，面向**自有站点迁移、源码找回、学习拆解**等场景。请遵守法律与目标站点条款：

- **可以：** 克隆你拥有或已获授权的网站；用克隆结果做迁移、学习或内部重建
- **不可以：** 用于钓鱼、仿冒登录页、冒充品牌；把别人的设计/文案/Logo 当成自己的对外发布
- **先确认：** 部分站点禁止抓取或复制；请先阅读其服务条款与 robots/版权声明
- **留痕：** 各站点 `CLONE_TARGETS.txt` 与 `.generator-version` 便于记录来源与时间

克隆物默认是视觉/前端还原，**不包含**真实后端、鉴权与生产数据。对外部署前请自行替换品牌资产并取得合法授权。

## 脚本一览

| 脚本 | 作用 |
| ---- | ---- |
| `scripts/bootstrap-template.sh` | 首次克隆生成器（幂等） |
| `scripts/new-site.sh … [--install] [--with-docker]` | 创建站点（Docker 可选） |
| `scripts/batch-clone.sh … [--install] [--with-docker]` | 批量建站 + 后续清单 |
| `scripts/site-status.sh` | 状态与下一步 |
| `scripts/install-deps.sh` / `prune-deps.sh` | 按需装 / 清依赖 |
| `scripts/update-template.sh` | 更新生成器并重建命令（缺则 bootstrap） |
| `scripts/update-sites.sh … [--deps] [--docker] [--install]` | 同步配置 |
| `scripts/build-clone-command.sh` | 重建 `/clone-website` + 同步 Playwright MCP |
| `scripts/check.sh` | 最小验收（shellcheck + pins + clone-website.md） |

## 说明

- `SITE_INCLUDE` / `SITE_INCLUDE_DOCKER` / `MANAGED_FILES` / `DEPS_FILES` 定义在 `scripts/lib.sh`
- 路径可用 `TEMPLATE_DIR` / `SITES_DIR` / `TEMPLATE_REPO` / `TEMPLATE_BRANCH` 覆盖
