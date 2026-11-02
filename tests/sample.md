# 渲染测试文档 —— 已自动刷新 ✔

普通段落，含 **粗体**、*斜体*、~~删除线~~、`行内代码`、[链接](https://example.com) 与自动链接 https://github.com 。

## 图片（相对路径）

![测试图](assets/logo.png)

## 表格

| 语言 | 类型 | 原生 arm64 |
| :--- | :---: | ---: |
| Swift | 编译 | 是 |
| Python | 解释 | 是 |

## 代码块（Prism 高亮）

```swift
final class Viewer: NSWindowController {
    let webView: WKWebView   // 注释应着色
    func render() { webView.loadHTMLString(html, baseURL: nil) }
}
```

```bash
clang -arch arm64 -O2 -c hoedown.c && echo "ok"
```

## 引用与列表

> 引用块第一行
> 引用块第二行

1. 有序一
2. 有序二

- [x] 已完成的任务
- [ ] 未完成的任务

## 脚注

正文引用脚注[^a]。

[^a]: 脚注内容在这里。
