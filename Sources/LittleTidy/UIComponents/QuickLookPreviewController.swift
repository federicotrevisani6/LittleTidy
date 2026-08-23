import AppKit
import QuickLook
import QuickLookUI

@MainActor
final class QuickLookPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var urls: [URL] = []

    func preview(_ urls: [URL]) {
        self.urls = urls.filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !self.urls.isEmpty, let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
