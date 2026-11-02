# 第三方组件与许可

本项目的自有代码以 MIT 许可发布（见 `LICENSE`）。它同时包含或衍生自以下
第三方作品，各自的许可原文收录在 `licenses/` 目录。

| 组件 | 用途 | 许可 | 原文 |
| --- | --- | --- | --- |
| [MacDown](https://github.com/MacDownApp/macdown) | 渲染管线的设计参考；6 套主题 CSS 与 `hoedown_html_patch` 取自本项目 | MIT © 2014 Tzu-ping Chung | `licenses/MacDown-MIT.txt` |
| [hoedown](https://github.com/hoedown/hoedown) | Markdown 解析内核（`Sources/choedown/`） | ISC 类 © 2008 Natacha Porté 等 | `licenses/hoedown-ISC.txt` |
| [Prism](https://prismjs.com) | 代码块语法高亮（`Resources/prism/`） | MIT © 2012 Lea Verou | `licenses/Prism-MIT.txt` |
| [MathJax](https://www.mathjax.org) | 数学公式排版（`Resources/mathjax/`） | Apache-2.0 | `licenses/MathJax-Apache-2.0.txt` |

## 说明

- **不是 MacDown 的复刻版**：本项目复用了 MacDown 的渲染内核（hoedown 及其补丁）
  与主题样式，但外壳（窗口、渲染流程、查找、导出）是为“只读阅读 + 导出”重新编写的。
- **`Resources/mathjax/mathjax.js`** 为 MathJax 3.2.2 官方 `es5/tex-svg.js` 构建产物的
  重命名副本（单文件、字形内嵌、可离线使用），未作修改。
- **`Resources/prism/prism.js`** 由 `tools/build_prism.js` 从 prismjs 1.29.0 官方包
  按依赖顺序合并而成（67 个语言组件）。
- 本仓库**不包含** MacDown 的完整源码，只包含上述被复用的部分。
