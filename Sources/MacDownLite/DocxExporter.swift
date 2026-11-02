import Foundation

// MARK: - Document model (mirrors Resources/export-model.js)

struct ExportModel: Decodable {
    let blocks: [ExportBlock]
    let math: [ExportMath]
    let images: [ExportImage]
    let title: String
}

struct ExportBlock: Decodable {
    let kind: String
    let quoteDepth: Int?
    let level: Int?
    let headingLevel: Int?
    let ordered: Bool?
    let checked: Bool?
    let runs: [ExportRun]?
    let text: String?
    let lang: String?
    let rows: [[ExportCell]]?
    let cols: Int?
}

struct ExportCell: Decodable {
    let runs: [ExportRun]
    let header: Bool
}

struct ExportRun: Decodable {
    let text: String?
    let bold: Bool?
    let italic: Bool?
    let strike: Bool?
    let underline: Bool?
    let highlight: Bool?
    let superscript: Bool?
    let `subscript`: Bool?
    let code: Bool?
    let lineBreak: Bool?
    let link: String?
    let mathId: String?
    let imageIndex: Int?
}

struct ExportMath: Decodable {
    let id: String
    let display: Bool
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    /// Self-contained SVG markup, rasterised by the host into a PNG part.
    let svg: String?
}

struct ExportImage: Decodable {
    let src: String
    let alt: String
    let w: Double
    let h: Double
}

// MARK: - Exporter

/// Turns the extracted model into a real `.docx` (OOXML) package.
///
/// Everything here is plain string building plus a ZIP container — no
/// third-party dependency. Fonts, sizes and colours follow the on-screen
/// “Word 文档” theme so the exported file looks like what the reader saw.
struct DocxExporter {

    let model: ExportModel
    /// Rendered PNG for each math id (formulas are exported as pictures).
    let mathImages: [String: Data]
    /// Raw bytes for each entry in `model.images`.
    let imageData: [Int: Data]
    /// PNG or JPEG, matching `imageData`.
    let imageExtensions: [Int: String]

    // Text column width in twips: A4 (11906) minus 3.17cm margins (1797 each).
    static let columnTwips = 11906 - 1797 * 2
    static let contentWidthEMU = 5277888                // 8312 twips, in EMU

    func build() -> Data {
        var rels: [(id: String, type: String, target: String, external: Bool)] = []
        var media: [(name: String, data: Data)] = []
        var nextRel = 1

        func addRel(_ type: String, _ target: String, external: Bool = false) -> String {
            let id = "rId\(nextRel)"; nextRel += 1
            rels.append((id, type, target, external))
            return id
        }

        // --- styles + numbering relationships ------------------------------
        let stylesId = addRel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "styles.xml")
        let numberingId = addRel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering", "numbering.xml")
        _ = stylesId; _ = numberingId

        // --- images --------------------------------------------------------
        var imageRelIds: [Int: String] = [:]
        for (index, _) in model.images.enumerated() {
            guard let data = imageData[index], !data.isEmpty else { continue }
            let ext = imageExtensions[index] ?? "png"
            let name = "image\(media.count + 1).\(ext)"
            media.append((name, data))
            imageRelIds[index] = addRel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
                                        "media/\(name)")
        }

        // --- math images ---------------------------------------------------
        var mathRelIds: [String: String] = [:]
        var mathSizes: [String: (w: Double, h: Double)] = [:]
        for m in model.math {
            guard let png = mathImages[m.id], !png.isEmpty else { continue }
            let name = "image\(media.count + 1).png"
            media.append((name, png))
            mathRelIds[m.id] = addRel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
                                      "media/\(name)")
            mathSizes[m.id] = (m.w, m.h)
        }

        // --- hyperlinks ----------------------------------------------------
        var linkRelIds: [String: String] = [:]
        for block in model.blocks {
            for run in (block.runs ?? []) where run.link != nil {
                if let url = run.link, linkRelIds[url] == nil {
                    linkRelIds[url] = addRel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
                                             url, external: true)
                }
            }
            for row in (block.rows ?? []) {
                for cell in row {
                    for run in cell.runs where run.link != nil {
                        if let url = run.link, linkRelIds[url] == nil {
                            linkRelIds[url] = addRel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
                                                     url, external: true)
                        }
                    }
                }
            }
        }

        // --- body ----------------------------------------------------------
        let ctx = RenderContext(imageRelIds: imageRelIds,
                                mathRelIds: mathRelIds,
                                mathSizes: mathSizes,
                                linkRelIds: linkRelIds)
        var renderer = BodyRenderer(context: ctx)
        let body = renderer.render(model.blocks)
        let allocatedNums = renderer.allocatedNums

        // --- package -------------------------------------------------------
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes())
        zip.add("_rels/.rels", rootRels())
        zip.add("word/document.xml", documentXML(body: body))
        zip.add("word/styles.xml", stylesXML())
        zip.add("word/numbering.xml", numberingXML(nums: allocatedNums))
        zip.add("word/_rels/document.xml.rels", documentRels(rels))
        for m in media { zip.add("word/media/\(m.name)", m.data) }
        return zip.archive()
    }

    // MARK: - Parts

    private func contentTypes() -> String {
        var defaults = """
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        """
        var seen = Set<String>()
        for ext in imageExtensions.values where !seen.contains(ext) {
            seen.insert(ext)
            let mime = ext == "jpg" || ext == "jpeg" ? "image/jpeg"
                     : ext == "gif" ? "image/gif"
                     : ext == "svg" ? "image/svg+xml" : "image/png"
            defaults += "\n  <Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          \(defaults)
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        </Types>
        """
    }

    private func rootRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    private func documentRels(_ rels: [(id: String, type: String, target: String, external: Bool)]) -> String {
        var items = ""
        for r in rels {
            let mode = r.external ? " TargetMode=\"External\"" : ""
            items += "\n  <Relationship Id=\"\(r.id)\" Type=\"\(r.type)\" Target=\"\(Self.attr(r.target))\"\(mode)/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(items)
        </Relationships>
        """
    }

    private func documentXML(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body>
        \(body)
        <w:sectPr>
          <w:pgSz w:w="11906" w:h="16838"/>
          <w:pgMar w:top="1440" w:right="1797" w:bottom="1440" w:left="1797" w:header="851" w:footer="992" w:gutter="0"/>
        </w:sectPr>
        </w:body>
        </w:document>
        """
    }

    /// Styles mirroring the on-screen “Word 文档” theme.
    private func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault><w:rPr>
              <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体" w:cs="Times New Roman"/>
              <w:sz w:val="24"/><w:szCs w:val="24"/>
            </w:rPr></w:rPrDefault>
            <w:pPrDefault><w:pPr>
              <w:spacing w:line="360" w:lineRule="auto" w:after="120"/>
              <w:jc w:val="both"/>
            </w:pPr></w:pPrDefault>
          </w:docDefaults>

          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/><w:qFormat/>
          </w:style>

          <w:style w:type="paragraph" w:styleId="BodyIndent">
            <w:name w:val="Body Indent"/><w:basedOn w:val="Normal"/>
            <w:pPr><w:ind w:firstLine="480"/></w:pPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/>
            <w:pPr><w:spacing w:before="360" w:after="180"/><w:jc w:val="left"/>
              <w:pBdr><w:bottom w:val="single" w:sz="12" w:space="2" w:color="1F3864"/></w:pBdr></w:pPr>
            <w:rPr><w:rFonts w:ascii="Heiti SC" w:hAnsi="Heiti SC" w:eastAsia="黑体"/>
              <w:b/><w:color w:val="1F3864"/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/>
            <w:pPr><w:spacing w:before="300" w:after="120"/><w:jc w:val="left"/></w:pPr>
            <w:rPr><w:rFonts w:ascii="Heiti SC" w:hAnsi="Heiti SC" w:eastAsia="黑体"/>
              <w:b/><w:color w:val="2E74B5"/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Heading3">
            <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:qFormat/>
            <w:pPr><w:spacing w:before="240" w:after="100"/><w:jc w:val="left"/></w:pPr>
            <w:rPr><w:rFonts w:ascii="Heiti SC" w:hAnsi="Heiti SC" w:eastAsia="黑体"/>
              <w:b/><w:color w:val="2E74B5"/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Heading4">
            <w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:qFormat/>
            <w:pPr><w:spacing w:before="200" w:after="80"/><w:jc w:val="left"/></w:pPr>
            <w:rPr><w:rFonts w:ascii="Heiti SC" w:hAnsi="Heiti SC" w:eastAsia="黑体"/>
              <w:b/><w:color w:val="333333"/><w:sz w:val="24"/></w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Code">
            <w:name w:val="Code"/><w:basedOn w:val="Normal"/>
            <w:pPr>
              <w:spacing w:line="259" w:lineRule="auto" w:before="60" w:after="60"/>
              <w:ind w:left="120" w:right="120"/>
              <w:jc w:val="left"/>
              <w:shd w:val="clear" w:color="auto" w:fill="F7F7F7"/>
            </w:pPr>
            <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:eastAsia="宋体"/>
              <w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Quote">
            <w:name w:val="Quote"/><w:basedOn w:val="Normal"/>
            <w:pPr>
              <w:ind w:left="480"/>
              <w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="BFBFBF"/></w:pBdr>
            </w:pPr>
            <w:rPr><w:color w:val="404040"/></w:rPr>
          </w:style>

          <w:style w:type="character" w:styleId="CodeChar">
            <w:name w:val="Code Char"/>
            <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:eastAsia="宋体"/>
              <w:sz w:val="21"/>
              <w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:rPr>
          </w:style>

          <w:style w:type="character" w:styleId="Hyperlink">
            <w:name w:val="Hyperlink"/>
            <w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr>
          </w:style>

          <w:style w:type="table" w:styleId="TableGrid">
            <w:name w:val="Table Grid"/>
            <w:tblPr>
              <w:tblBorders>
                <w:top w:val="single" w:sz="6" w:color="8EAADB"/>
                <w:left w:val="single" w:sz="6" w:color="8EAADB"/>
                <w:bottom w:val="single" w:sz="6" w:color="8EAADB"/>
                <w:right w:val="single" w:sz="6" w:color="8EAADB"/>
                <w:insideH w:val="single" w:sz="6" w:color="8EAADB"/>
                <w:insideV w:val="single" w:sz="6" w:color="8EAADB"/>
              </w:tblBorders>
            </w:tblPr>
          </w:style>
        </w:styles>
        """
    }

    private func numberingXML(nums: [(numId: Int, abstractId: Int)]) -> String {
        func levels(bullet: String?) -> String {
            var out = ""
            for lvl in 0..<9 {
                let indent = 720 + lvl * 360
                let text = bullet.map { _ in bullet! } ?? "%\(lvl + 1)."
                out += """
                <w:lvl w:ilvl="\(lvl)">
                  <w:start w:val="1"/>
                  <w:numFmt w:val="\(bullet == nil ? "decimal" : "bullet")"/>
                  <w:lvlText w:val="\(text)"/>
                  <w:lvlJc w:val="left"/>
                  <w:pPr><w:ind w:left="\(indent)" w:hanging="360"/></w:pPr>
                  <w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/></w:rPr>
                </w:lvl>
                """
            }
            return out
        }
        var numXML = ""
        for n in nums {
            numXML += "\n  <w:num w:numId=\"\(n.numId)\"><w:abstractNumId w:val=\"\(n.abstractId)\"/></w:num>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="0">
            <w:multiLevelType w:val="hybridMultilevel"/>
            \(levels(bullet: nil))
          </w:abstractNum>
          <w:abstractNum w:abstractNumId="1">
            <w:multiLevelType w:val="hybridMultilevel"/>
            \(levels(bullet: "\u{2022}"))
          </w:abstractNum>\(numXML)
        </w:numbering>
        """
    }

    // MARK: - Escaping helpers

    static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }

    static func attr(_ s: String) -> String {
        esc(s).replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Body rendering

/// Carries everything the body renderer needs to resolve references.
struct RenderContext {
    let imageRelIds: [Int: String]
    let mathRelIds: [String: String]
    let mathSizes: [String: (w: Double, h: Double)]
    let linkRelIds: [String: String]
}

struct BodyRenderer {
    let context: RenderContext
    private var drawingId = 0

    // numId allocation: a fresh instance whenever a list run breaks, so that
    // separate lists restart their numbering.
    private var currentListKey: String?
    private var numIdCounter = 2
    private var currentNumId = 0
    private var extraNums: [(numId: Int, abstractId: Int)] = []

    /// Every `<w:num>` the body referenced; numbering.xml must declare them.
    var allocatedNums: [(numId: Int, abstractId: Int)] { extraNums }

    mutating func render(_ blocks: [ExportBlock]) -> String {
        var out = ""
        for b in blocks { out += xml(for: b) }
        return out
    }

    // MARK: block dispatch

    private mutating func xml(for b: ExportBlock) -> String {
        switch b.kind {
        case "heading":  return heading(b)
        case "para":     return paragraph(b)
        case "code":     return codeBlock(b)
        case "list":     return listItem(b)
        case "table":    return table(b)
        case "hr":       return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:color=\"BFBFBF\"/></w:pBdr></w:pPr></w:p>"
        default:         return paragraph(b)
        }
    }

    private mutating func heading(_ b: ExportBlock) -> String {
        let lvl = min(4, max(1, b.headingLevel ?? 1))
        let runs = inlineXML(b.runs ?? [], baseStyle: nil)
        return paraXML(style: "Heading\(lvl)", indentFirstLine: false,
                       extraProps: "", runs: runs)
    }

    private mutating func paragraph(_ b: ExportBlock) -> String {
        let quote = (b.quoteDepth ?? 0) > 0
        let runs = inlineXML(b.runs ?? [], baseStyle: nil)
        if quote {
            return paraXML(style: "Quote", indentFirstLine: false, extraProps: "", runs: runs)
        }
        // export-model.js stamps every block with a numeric level, so a plain
        // top-level body paragraph is level 0 with no quote depth.
        let indent = (b.level ?? 0) == 0 && (b.quoteDepth ?? 0) == 0
        return paraXML(style: "Normal", indentFirstLine: indent, extraProps: "", runs: runs)
    }

    private mutating func codeBlock(_ b: ExportBlock) -> String {
        // Preserve line structure with explicit breaks inside one paragraph.
        let lines = (b.text ?? "").components(separatedBy: "\n")
        var runs = ""
        for (i, line) in lines.enumerated() {
            if i > 0 { runs += "<w:r><w:br/></w:r>" }
            runs += "<w:r><w:t xml:space=\"preserve\">\(DocxExporter.esc(line))</w:t></w:r>"
        }
        return paraXML(style: "Code", indentFirstLine: false, extraProps: "", runs: runs)
    }

    private mutating func listItem(_ b: ExportBlock) -> String {
        // Task-list items are rendered as a literal checkbox + text so the
        // state survives a round trip through Word.
        if let checked = b.checked {
            let glyph = checked ? "\u{2611} " : "\u{2610} "
            var runs = "<w:r><w:t xml:space=\"preserve\">\(DocxExporter.esc(glyph))</w:t></w:r>"
            runs += inlineXML(b.runs ?? [], baseStyle: nil)
            return paraXML(style: "Normal", indentFirstLine: false,
                           extraProps: "<w:ind w:left=\"720\"/>", runs: runs)
        }

        let ordered = b.ordered ?? false
        let level = min(8, max(0, b.level ?? 0))
        let key = "\(ordered ? "o" : "u")-\(b.quoteDepth ?? 0)"
        if key != currentListKey {
            currentListKey = key
            numIdCounter += 1
            // Reuse the two abstract definitions; a new num restarts counting.
            extraNums.append((numIdCounter, ordered ? 0 : 1))
            currentNumId = numIdCounter
        }
        let props = """
        <w:pPr><w:pStyle w:val="Normal"/><w:numPr><w:ilvl w:val="\(level)"/><w:numId w:val="\(currentNumId)"/></w:numPr>\
        <w:spacing w:after="60"/></w:pPr>
        """
        return "<w:p>\(props)\(inlineXML(b.runs ?? [], baseStyle: nil))</w:p>"
    }

    private mutating func table(_ b: ExportBlock) -> String {
        let rows = b.rows ?? []
        let cols = max(1, b.cols ?? 1)
        let colTwips = DocxExporter.columnTwips / cols

        var grid = ""
        for _ in 0..<cols { grid += "<w:gridCol w:w=\"\(colTwips)\"/>" }

        var body = ""
        for row in rows {
            body += "<w:tr>"
            for c in 0..<cols {
                let cell = c < row.count ? row[c] : ExportCell(runs: [], header: false)
                let shade = cell.header ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"D9E2F3\"/>" : ""
                let runs = inlineXML(cell.runs, baseStyle: nil)
                let jc = cell.header ? "<w:jc w:val=\"center\"/>" : "<w:jc w:val=\"left\"/>"
                body += """
                <w:tc><w:tcPr><w:tcW w:w="\(colTwips)" w:type="dxa"/>\(shade)<w:vAlign w:val="center"/></w:tcPr>\
                <w:p><w:pPr><w:spacing w:line="300" w:lineRule="auto" w:after="0"/>\(jc)</w:pPr>\(runs)</w:p></w:tc>
                """
            }
            body += "</w:tr>"
        }

        return """
        <w:tbl>
          <w:tblPr>
            <w:tblStyle w:val="TableGrid"/>
            <w:tblW w:w="\(DocxExporter.columnTwips)" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:color="8EAADB"/><w:left w:val="single" w:sz="6" w:color="8EAADB"/>
              <w:bottom w:val="single" w:sz="6" w:color="8EAADB"/><w:right w:val="single" w:sz="6" w:color="8EAADB"/>
              <w:insideH w:val="single" w:sz="6" w:color="8EAADB"/><w:insideV w:val="single" w:sz="6" w:color="8EAADB"/>
            </w:tblBorders>
            <w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="90" w:type="dxa"/>
              <w:bottom w:w="40" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tblCellMar>
          </w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(body)
        </w:tbl>
        <w:p><w:pPr><w:spacing w:after="0"/></w:pPr></w:p>
        """
    }

    // MARK: paragraph / run assembly

    private func paraXML(style: String, indentFirstLine: Bool,
                         extraProps: String, runs: String) -> String {
        var props = "<w:pPr><w:pStyle w:val=\"\(style)\"/>"
        if indentFirstLine { props += "<w:ind w:firstLine=\"480\"/>" }
        props += extraProps
        props += "</w:pPr>"
        return "<w:p>\(props)\(runs)</w:p>"
    }

    private mutating func inlineXML(_ runs: [ExportRun], baseStyle: String?) -> String {
        var out = ""
        for r in runs { out += self.xml(for: r) }
        return out
    }

    private mutating func xml(for r: ExportRun) -> String {
        if r.lineBreak == true { return "<w:r><w:br/></w:r>" }

        if let index = r.imageIndex, let relId = context.imageRelIds[index] {
            return drawing(relId: relId, width: nil, height: nil, name: "image\(index)")
        }
        if let mid = r.mathId, let relId = context.mathRelIds[mid] {
            let size = context.mathSizes[mid]
            return drawing(relId: relId, width: size?.w, height: size?.h, name: "math-\(mid)")
        }

        // Hyperlink wrapping its own runs.
        if let url = r.link, let relId = context.linkRelIds[url] {
            let inner = runXML(r, style: "Hyperlink")
            return "<w:hyperlink r:id=\"\(relId)\">\(inner)</w:hyperlink>"
        }
        return runXML(r, style: r.code == true ? "CodeChar" : nil)
    }

    private func runXML(_ r: ExportRun, style: String?) -> String {
        var props = "<w:rPr>"
        if let style { props += "<w:rStyle w:val=\"\(style)\"/>" }
        if r.bold == true { props += "<w:b/>" }
        if r.italic == true { props += "<w:i/>" }
        if r.strike == true { props += "<w:strike/>" }
        if r.underline == true { props += "<w:u w:val=\"single\"/>" }
        if r.highlight == true { props += "<w:highlight w:val=\"yellow\"/>" }
        if r.superscript == true { props += "<w:vertAlign w:val=\"superscript\"/>" }
        if r.subscript == true { props += "<w:vertAlign w:val=\"subscript\"/>" }
        props += "</w:rPr>"
        if props == "<w:rPr></w:rPr>" { props = "" }

        let text = DocxExporter.esc(r.text ?? "")
        return "<w:r>\(props)<w:t xml:space=\"preserve\">\(text)</w:t></w:r>"
    }

    /// Inline picture (EMU sizing, capped to the text column).
    private mutating func drawing(relId: String, width: Double?, height: Double?,
                                  name: String) -> String {
        drawingId += 1
        let w = width ?? 200
        var h = height ?? 40
        if h <= 0 { h = w * 0.6 }
        let maxEMU = Double(DocxExporter.contentWidthEMU)
        var cx = w * 9525.0                    // CSS px -> EMU
        var cy = h * 9525.0
        if cx > maxEMU {
            let scale = maxEMU / cx
            cx *= scale; cy *= scale
        }
        if cx < 9525 { cx = 9525 }
        if cy < 9525 { cy = 9525 }

        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">
          <wp:extent cx="\(Int(cx))" cy="\(Int(cy))"/>
          <wp:effectExtent l="0" t="0" r="0" b="0"/>
          <wp:docPr id="\(drawingId)" name="\(DocxExporter.attr(name))"/>
          <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <pic:pic>
              <pic:nvPicPr><pic:cNvPr id="\(drawingId)" name="\(DocxExporter.attr(name))"/><pic:cNvPicPr/></pic:nvPicPr>
              <pic:blipFill><a:blip r:embed="\(relId)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
              <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(Int(cx))" cy="\(Int(cy))"/></a:xfrm>
                <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
            </pic:pic>
          </a:graphicData></a:graphic>
        </wp:inline></w:drawing></w:r>
        """
    }
}
