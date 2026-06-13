import Foundation
import Testing
@testable import MacCleanerCore

@Suite("Large file analyzer")
struct LargeFileAnalyzerTests {
    @Test("ranks old installer-like files in Downloads above newer generic files")
    func ranksLargeFiles() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let analyzer = LargeFileAnalyzer(now: { now })
        let downloadsInstaller = FileRecord(
            url: URL(fileURLWithPath: "/tmp/Downloads/Installer.dmg"),
            fileSize: 900_000_000,
            lastAccessDate: now.addingTimeInterval(-200 * 86_400)
        )
        let genericFile = FileRecord(
            url: URL(fileURLWithPath: "/tmp/Documents/archive.data"),
            fileSize: 1_500_000_000,
            lastAccessDate: now
        )

        let candidates = analyzer.findLargeFiles(in: [genericFile, downloadsInstaller], threshold: 500_000_000)

        #expect(candidates.count == 2)
        #expect(candidates[0].file.url == downloadsInstaller.url)
        #expect(candidates[0].reason == "Large file in Downloads.")
    }

    @Test("skips protected package-like libraries")
    func skipsProtectedPackages() {
        let analyzer = LargeFileAnalyzer()
        let photoLibrary = FileRecord(
            url: URL(fileURLWithPath: "/tmp/Pictures/Main.photoslibrary"),
            fileSize: 50_000_000_000
        )

        let candidates = analyzer.findLargeFiles(in: [photoLibrary], threshold: 500_000_000)

        #expect(candidates.isEmpty)
    }
}
