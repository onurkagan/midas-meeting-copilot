import AppKit
import SwiftUI
import WebKit

/// The map to share. The daemon writes the Markdown and the HTML (with the picture and
/// every item's explanation); the PDF is that HTML printed on A4 pages.
enum MapExportFormat: String, CaseIterable, Identifiable {
    case pdf, md, html
    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .md: "Markdown"
        case .html: "HTML"
        }
    }
}

/// Prints an HTML file to a paginated PDF with WebKit, in a window that is never shown.
@MainActor
final class PDFPrinter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow
    private let output: URL
    private var done: ((Bool) -> Void)?
    /// Kept alive until their PDF is written.
    private static var running: [PDFPrinter] = []

    static func print(_ html: URL, to output: URL, done: @escaping (Bool) -> Void) {
        let printer = PDFPrinter(output: output, done: done)
        running.append(printer)
        printer.webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    private init(output: URL, done: @escaping (Bool) -> Void) {
        let page = NSRect(x: 0, y: 0, width: 794, height: 1123)  // A4 at 96 dpi
        webView = WKWebView(frame: page)
        window = NSWindow(contentRect: page, styleMask: .borderless, backing: .buffered, defer: false)
        window.sharingType = .none
        window.contentView = webView
        self.output = output
        self.done = done
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        try? FileManager.default.removeItem(at: output)
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89)  // A4 in points
        for side in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] { info[keyPath: side] = 36 }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: self, didRun: #selector(printed(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printed(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if success, FileManager.default.fileExists(atPath: output.path) {
            finish(true)
            return
        }
        // Printing failed: one long page is still a PDF to share.
        webView.createPDF { result in
            if case .success(let data) = result, (try? data.write(to: self.output)) != nil {
                self.finish(true)
            } else {
                self.finish(false)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        done?(ok)
        done = nil
        Self.running.removeAll { $0 === self }
    }
}

/// Export · PDF · Markdown · HTML, as buttons in a row: a pop-up menu would show in a
/// screen share.
struct MapExportButtons: View {
    @ObservedObject var client: MidasClient
    var compact = false
    @Environment(\.tide) private var tide

    var body: some View {
        HStack(spacing: 6) {
            if client.exporting != nil {
                ProgressView().controlSize(.mini)
                Text("Exporting…").foregroundStyle(tide.muted)
            } else {
                Text(compact ? "Export" : "Export as").foregroundStyle(tide.muted)
            }
            ForEach(MapExportFormat.allCases) { format in
                Button(compact && format == .md ? "MD" : format.label) { client.exportMap(format) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(client.exporting != nil || client.meetingMap?.nodes.isEmpty != false)
                    .help("Save the map as \(format.label), with every item's explanation, next to the meeting log, and show it in Finder")
            }
        }
        .font(Tide.font(compact ? 11.5 : 12, .semibold))
    }
}
