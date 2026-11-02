#!/usr/bin/env bash
# Regression suite for MacDown Lite: math preprocessing + in-page find.
# Usage: ./tests/run_regression.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

OBJ="$HERE/build/obj"
if [ ! -f "$OBJ/libhoedown.a" ]; then
  echo "先运行 ./build.sh 以生成 libhoedown.a" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== 1/4  MathPreprocessor 单元测试 ==="
mkdir -p "$WORK/mp"
cp tests/regression/mathpreprocessor_test.swift "$WORK/mp/main.swift"
swiftc -O -swift-version 5 Sources/MacDownLite/MathPreprocessor.swift \
  "$WORK/mp/main.swift" -o "$WORK/mp/run"
"$WORK/mp/run"

echo
echo "=== 2/4  页面内查找 + MathJax 端到端 ==="
mkdir -p "$WORK/e2e"
cp tests/regression/find_e2e_test.swift "$WORK/e2e/main.swift"
swiftc -O -swift-version 5 \
  Sources/MacDownLite/Settings.swift Sources/MacDownLite/Resources.swift \
  Sources/MacDownLite/ThemeManager.swift Sources/MacDownLite/MarkdownRenderer.swift \
  Sources/MacDownLite/MathPreprocessor.swift Sources/MacDownLite/HTMLBuilder.swift \
  Sources/MacDownLite/AssetSchemeHandler.swift "$WORK/e2e/main.swift" \
  -I Sources/choedown -L "$OBJ" -lhoedown -framework AppKit -framework WebKit \
  -o "$WORK/e2e/run"

echo
echo "=== 3/4  打印媒体语义（纸张模型仅在屏幕生效） ==="
mkdir -p "$WORK/print"
cp tests/regression/print_media_test.swift "$WORK/print/main.swift"
swiftc -O -swift-version 5 \
  Sources/MacDownLite/Settings.swift Sources/MacDownLite/Resources.swift \
  Sources/MacDownLite/ThemeManager.swift Sources/MacDownLite/MarkdownRenderer.swift \
  Sources/MacDownLite/MathPreprocessor.swift Sources/MacDownLite/HTMLBuilder.swift \
  Sources/MacDownLite/AssetSchemeHandler.swift "$WORK/print/main.swift" \
  -I Sources/choedown -L "$OBJ" -lhoedown -framework AppKit -framework WebKit \
  -o "$WORK/print/run"

echo
echo "=== 4/4  导出（Word .docx / PDF） ==="
mkdir -p "$WORK/exp"
cp tests/regression/export_test.swift "$WORK/exp/main.swift"
swiftc -O -swift-version 5 \
  Sources/MacDownLite/Settings.swift Sources/MacDownLite/Resources.swift \
  Sources/MacDownLite/ThemeManager.swift Sources/MacDownLite/MarkdownRenderer.swift \
  Sources/MacDownLite/MathPreprocessor.swift Sources/MacDownLite/HTMLBuilder.swift \
  Sources/MacDownLite/AssetSchemeHandler.swift Sources/MacDownLite/ZipWriter.swift \
  Sources/MacDownLite/DocxExporter.swift Sources/MacDownLite/SVGRasterizer.swift \
  "$WORK/exp/main.swift" \
  -I Sources/choedown -L "$OBJ" -lhoedown \
  -framework AppKit -framework WebKit -framework PDFKit \
  -o "$WORK/exp/run"
"$WORK/exp/run" "$WORK/out.docx" "$WORK/out.pdf" tests/word_demo.md

echo
echo "--- 系统级 ZIP 校验 ---"
if unzip -t "$WORK/out.docx" >/dev/null 2>&1; then
  echo "  ok   unzip -t 通过"
else
  echo "  FAIL unzip -t 失败"
  exit 1
fi
"$WORK/print/run"
"$WORK/e2e/run"
