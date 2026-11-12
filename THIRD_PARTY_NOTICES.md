# 第三方项目与许可 / Third-party notices

语界输入法使用或衍生自以下项目。各项目的版权归原作者所有。

| 项目 | 用途 | 许可 |
|---|---|---|
| [Squirrel 鼠须管](https://github.com/rime/squirrel) | 本项目的上游代码（macOS 输入法前端） | GPL-3.0 |
| [librime](https://github.com/rime/librime) | Rime 输入法引擎（git 子模块，构建时下载预编译库） | BSD-3-Clause |
| [plum 东风破](https://github.com/rime/plum) | Rime 输入方案安装工具（git 子模块） | LGPL-3.0 |
| Rime 输入方案（如 rime-luna-pinyin、rime-prelude 等） | 构建时由 plum 下载并打包 | 各方案自身许可，多为 LGPL-3.0 |
| [OpenCC](https://github.com/BYVoid/OpenCC) | 繁简转换数据（随 librime 依赖下载） | Apache-2.0 |
| [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict) | 英语候选翻译词库 `data/candidate_translator/dictionary` 的来源 | CC BY-SA 4.0 |

## CC-CEDICT 衍生数据

`data/candidate_translator/dictionary/` 中的词库由 `tools/build_dictionary.py` 从 CC-CEDICT 生成，经过重新排序和清理，并合并了 `tools/dictionary_overrides.tsv` 中的人工修正。该词库及修正文件按 **CC BY-SA 4.0** 发布，详见 [data/candidate_translator/NOTICE.md](data/candidate_translator/NOTICE.md)。

## Apple 翻译

非英语语言以及词库未收录的英语词条，使用 macOS 自带的 Translation 框架在本机翻译。语言模型由 macOS 下载和管理，不随本项目分发。
