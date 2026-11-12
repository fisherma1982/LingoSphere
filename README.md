# 语界输入法 · LingoSphere

打中文，顺手出外语。

语界是一款 macOS 中文输入法：在 [Rime 输入法引擎](https://rime.im) 与 [鼠须管](https://github.com/rime/squirrel) 的基础上，为每个候选词实时显示外语译文，并可以直接把译文上屏。翻译全部在 Mac 本机完成，不联网、不上传输入内容。

- 系统要求：macOS 15 及以上（Apple 芯片与 Intel 均可）
- 翻译语言：英语、日语、韩语、德语、法语、西班牙语、葡萄牙语（巴西）

## 功能

**候选词实时翻译**
输入时每个候选词旁边显示所选语言的译文。英语内置约 20 万条 CC-CEDICT 中英词条，可以即时显示；其他语言使用 macOS 自带的 Apple 翻译（Translation）本机模型。

**译文直接上屏**

| 操作 | 效果 |
|---|---|
| `⌥ Option` + `空格` | 上屏当前高亮候选词的译文 |
| `⌥ Option` + `数字` | 上屏对应候选词的译文 |
| 一词多义时 | 先弹出义项列表（如 小 → small / tiny / few），再按数字选择 |

菜单中开启“选词时上屏译文”后，行为互换：直接选词上屏译文，按住 `⌥ Option` 才上屏中文。

**随时切换语言**
从输入法菜单的“候选翻译”切换目标语言、关闭翻译，或管理 Apple 本机语言模型。七种语言分别缓存，不会混用。

**可视化设置**
“语界设置…”集中管理候选数量、键盘布局、候选窗主题（语界清新 / 系统原生 / 石墨深色）、字体字号、间距与透明度，无需手动编辑 YAML。保存前会自动备份已有的 `squirrel.custom.yaml` 和 `default.custom.yaml`。

## 安装

到本仓库的 [Releases](../../releases) 页面下载最新的 `.pkg` 安装包，双击安装：

1. 输入一次 Mac 密码。
2. 系统提示“允许 TextInputMenuAgent 启用语界”时点击“允许”。
3. 按提示注销并重新登录一次。
4. 在系统输入法菜单中选择“语界（简体）”。

语界使用独立的 Bundle ID 和输入源 ID。如果之前装过鼠须管，旧程序会被备份到 `/Library/Application Support/LingoSphere/backups/`。个人词库和配置保存在 `~/Library/Rime`，不会被删除。

首次使用某种非英语语言时，macOS 会提示下载对应的翻译模型，下载一次即可离线使用。

## 从源码构建

需要 Xcode 16 或更新版本。

```sh
git clone --recursive <本仓库地址>
cd <仓库目录>

# 下载 librime 预编译库、OpenCC 数据与默认输入方案
./action-install.sh

# 构建通用版（arm64 + x86_64）安装包，输出到 dist/
./scripts/build-distributable-pkg.sh
```

默认使用本机临时签名（ad-hoc），适合自测。正式分发请用 Developer ID 签名并公证，参见 `Makefile` 中的 `DEV_ID` 相关步骤。

### 重新生成英语词库

英语词库由 `tools/build_dictionary.py` 从 CC-CEDICT 生成：合并同一词条的所有读音，日常义项排在专名和注释前面，并去掉拼音、繁简对照和异体字说明。常用词的人工修正放在 `tools/dictionary_overrides.tsv`。

```sh
curl -LO https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz
python3 tools/build_dictionary.py \
  --input cedict_1_0_ts_utf-8_mdbg.txt.gz \
  --output data/candidate_translator/dictionary \
  --overrides tools/dictionary_overrides.tsv
```

## 主要代码

| 文件 | 内容 |
|---|---|
| `sources/AppleCandidateTranslator.swift` | 候选翻译：本机词库、Apple 翻译会话、缓存、义项拆分 |
| `sources/SquirrelInputController.swift` | 按键处理，含 ⌥ 上屏译文与义项选择 |
| `sources/LingoSphereSettings.swift` | “语界设置…”界面 |
| `sources/LingoSphereIdentity.swift` | 应用与输入源标识 |
| `scripts/build-distributable-pkg.sh` | 打包与安装包自检 |
| `tools/` | 词库生成脚本、功能演示视频脚本 |

## 授权

语界是 [鼠须管 Squirrel](https://github.com/rime/squirrel) 的衍生作品，整体按 **GNU GPL v3** 发布，见 [LICENSE.txt](LICENSE.txt)。所用第三方项目及其许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

“语界 / LingoSphere”是本项目的独立名称，不是 Rime 官方发行版。Rime 与鼠须管的使用问题请到上游项目反馈。

上游鼠须管的原版说明与更新记录保留在 [INSTALL.md](INSTALL.md) 和 [CHANGELOG.md](CHANGELOG.md)。
