import Foundation
import Testing
@testable import LittleTidyCore

@Suite("Cache analyzer")
struct CacheAnalyzerTests {
    @Test("reports app caches, DerivedData, and dev tool caches above the minimum size")
    func findsCaches() throws {
        let home = try TemporaryDirectory().url

        let safariCache = home.appendingPathComponent("Library/Caches/com.apple.Safari", isDirectory: true)
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        let cargoCache = home.appendingPathComponent(".cargo/registry/cache", isDirectory: true)
        let uvCache = home.appendingPathComponent(".cache/uv", isDirectory: true)
        let tinyCache = home.appendingPathComponent("Library/Caches/com.example.tiny", isDirectory: true)
        for directory in [safariCache, derivedData, npmCache, cargoCache, uvCache, tinyCache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Data(repeating: 1, count: 2_000_000).write(to: safariCache.appendingPathComponent("blob.bin"))
        try Data(repeating: 2, count: 3_000_000).write(to: derivedData.appendingPathComponent("build.o"))
        try Data(repeating: 3, count: 1_500_000).write(to: npmCache.appendingPathComponent("pkg.tgz"))
        try Data(repeating: 4, count: 2_500_000).write(to: cargoCache.appendingPathComponent("cargo.bin"))
        try Data(repeating: 5, count: 1_200_000).write(to: uvCache.appendingPathComponent("uv.bin"))
        try Data(repeating: 6, count: 10_000).write(to: tinyCache.appendingPathComponent("small.bin"))

        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1_000_000)

        // Sorted largest first; tiny cache below the threshold is excluded.
        #expect(candidates.count == 5)
        #expect(candidates.first?.displayName == "Xcode DerivedData")
        #expect(candidates.contains { $0.displayName == "Safari" })
        #expect(candidates.contains { $0.displayName == "npm cache" })
        #expect(candidates.contains { $0.displayName == "Cargo registry cache" })
        #expect(candidates.contains { $0.displayName == "uv cache" })
        #expect(!candidates.contains { $0.url == tinyCache })
        #expect(candidates.allSatisfy { $0.sizeBytes >= 1_000_000 })
    }

    @Test("finds sandbox caches without offering app documents or Maven artifacts")
    func sandboxCoverage() throws {
        let home = try TemporaryDirectory().url.resolvingSymlinksInPath()
        let cache = home.appendingPathComponent("Library/Containers/com.example.app/Data/Library/Caches")
        let documents = home.appendingPathComponent("Library/Containers/com.example.app/Data/Documents")
        let maven = home.appendingPathComponent(".m2/repository")
        for directory in [cache, documents, maven] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: directory.appendingPathComponent("data"))
        }
        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1)
        #expect(candidates.map { $0.url.resolvingSymlinksInPath().standardized.path } == [cache.resolvingSymlinksInPath().standardized.path])
    }

    @Test("does not offer a symlinked cache target")
    func excludesSymlinks() throws {
        let home = try TemporaryDirectory().url.resolvingSymlinksInPath()
        let caches = home.appendingPathComponent("Library/Caches")
        let documents = home.appendingPathComponent("Documents")
        for directory in [caches, documents] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 8192).write(to: documents.appendingPathComponent("data"))
        try FileManager.default.createSymbolicLink(at: caches.appendingPathComponent("linked"), withDestinationURL: documents)
        #expect(try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1).isEmpty)
    }

    @Test("returns nothing when no cache locations exist")
    func emptyWhenAbsent() throws {
        let home = try TemporaryDirectory().url
        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1_000_000)
        #expect(candidates.isEmpty)
    }

    @Test("finds macOS framework caches, group container caches, logs, and Electron sub-caches without touching app databases")
    func expandedMacOSHierarchies() throws {
        let home = try TemporaryDirectory().url.resolvingSymlinksInPath()

        let groupCache = home.appendingPathComponent("Library/Group Containers/group.com.example.suite/Library/Caches", isDirectory: true)
        let groupDatabase = home.appendingPathComponent("Library/Group Containers/group.com.example.suite/Database", isDirectory: true)
        let httpStorageCache = home.appendingPathComponent("Library/HTTPStorages/com.apple.Safari/fsCachedData", isDirectory: true)
        let httpStorageCookies = home.appendingPathComponent("Library/HTTPStorages/com.apple.Safari", isDirectory: true)
        let webkitNetworkCache = home.appendingPathComponent("Library/WebKit/com.apple.Safari/WebsiteData/NetworkCache", isDirectory: true)
        let webkitLocalStorage = home.appendingPathComponent("Library/WebKit/com.apple.Safari/WebsiteData/LocalStorage", isDirectory: true)
        let savedState = home.appendingPathComponent("Library/Saved Application State/com.tinyspeck.slackmacgap.savedState", isDirectory: true)
        let appLog = home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let electronGPUCache = home.appendingPathComponent("Library/Application Support/Slack/GPUCache", isDirectory: true)
        let electronLocalStorage = home.appendingPathComponent("Library/Application Support/Slack/Local Storage", isDirectory: true)

        for dir in [
            groupCache, groupDatabase, httpStorageCache, webkitNetworkCache,
            webkitLocalStorage, savedState, appLog, electronGPUCache, electronLocalStorage
        ] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 16_384).write(to: dir.appendingPathComponent("blob.bin"))
        }
        try Data(repeating: 9, count: 16_384).write(to: httpStorageCookies.appendingPathComponent("httpstorages.sqlite"))

        let candidates = try CacheAnalyzer(homeDirectory: home).findCaches(minimumSize: 1)
        let paths = Set(candidates.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })

        #expect(paths.contains(groupCache.standardizedFileURL.path))
        #expect(paths.contains(httpStorageCache.standardizedFileURL.path))
        #expect(paths.contains(webkitNetworkCache.standardizedFileURL.path))
        #expect(paths.contains(savedState.standardizedFileURL.path))
        #expect(paths.contains(appLog.standardizedFileURL.path))
        #expect(paths.contains(electronGPUCache.standardizedFileURL.path))

        // Critical safety checks: never touch group container root/databases, cookies sqlite, LocalStorage, or Application Support root.
        #expect(!paths.contains(groupDatabase.standardizedFileURL.path))
        #expect(!paths.contains(httpStorageCookies.standardizedFileURL.path))
        #expect(!paths.contains(webkitLocalStorage.standardizedFileURL.path))
        #expect(!paths.contains(electronLocalStorage.standardizedFileURL.path))
    }

    @Test("discovers verified per-project build folders and ignores unverified folders with the same name")
    func projectBuildScannerRequiresSiblingManifests() throws {
        let workspace = try TemporaryDirectory().url.resolvingSymlinksInPath()

        // 1. Swift Package (.build + Package.swift)
        let swiftPkg = workspace.appendingPathComponent("SwiftApp", isDirectory: true)
        let swiftBuild = swiftPkg.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftBuild, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.0\n".utf8).write(to: swiftPkg.appendingPathComponent("Package.swift"))
        try Data(repeating: 1, count: 16_384).write(to: swiftBuild.appendingPathComponent("debug.o"))

        // 2. Rust Cargo (target + Cargo.toml)
        let rustPkg = workspace.appendingPathComponent("RustService", isDirectory: true)
        let rustTarget = rustPkg.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: rustTarget, withIntermediateDirectories: true)
        try Data("[package]\nname = \"svc\"\n".utf8).write(to: rustPkg.appendingPathComponent("Cargo.toml"))
        try Data(repeating: 2, count: 16_384).write(to: rustTarget.appendingPathComponent("lib.rlib"))

        // 3. Web App (node_modules + .next + package.json)
        let webApp = workspace.appendingPathComponent("WebPortal", isDirectory: true)
        let nodeModules = webApp.appendingPathComponent("node_modules", isDirectory: true)
        let nextBuild = webApp.appendingPathComponent(".next", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nextBuild, withIntermediateDirectories: true)
        try Data("{\"name\":\"web\"}\n".utf8).write(to: webApp.appendingPathComponent("package.json"))
        try Data(repeating: 3, count: 16_384).write(to: nodeModules.appendingPathComponent("bundle.js"))
        try Data(repeating: 4, count: 16_384).write(to: nextBuild.appendingPathComponent("server.js"))

        // 4. CMake (build + CMakeCache.txt + CMakeFiles)
        let cmakeApp = workspace.appendingPathComponent("CppEngine", isDirectory: true)
        let cmakeBuild = cmakeApp.appendingPathComponent("build/CMakeFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: cmakeBuild, withIntermediateDirectories: true)
        try Data("CMAKE_CACHEFILE_DIR:INTERNAL=/tmp\n".utf8).write(to: cmakeApp.appendingPathComponent("build/CMakeCache.txt"))
        try Data(repeating: 5, count: 16_384).write(to: cmakeBuild.appendingPathComponent("engine.o"))

        // 5. Python virtualenv (.venv + pyvenv.cfg + pyproject.toml)
        let pyApp = workspace.appendingPathComponent("MLService", isDirectory: true)
        let pyVenv = pyApp.appendingPathComponent(".venv", isDirectory: true)
        try FileManager.default.createDirectory(at: pyVenv, withIntermediateDirectories: true)
        try Data("[project]\nname = \"ml\"\n".utf8).write(to: pyApp.appendingPathComponent("pyproject.toml"))
        try Data("home = /usr/bin\n".utf8).write(to: pyVenv.appendingPathComponent("pyvenv.cfg"))
        try Data(repeating: 6, count: 16_384).write(to: pyVenv.appendingPathComponent("site.bin"))

        // 6. CACHEDIR.TAG standard directory
        let customCache = workspace.appendingPathComponent("CustomTool/my-custom-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: customCache, withIntermediateDirectories: true)
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n# Cache directory tag\n".utf8)
            .write(to: customCache.appendingPathComponent("CACHEDIR.TAG"))
        try Data(repeating: 7, count: 16_384).write(to: customCache.appendingPathComponent("cache.dat"))

        // 7. Unverified user folders named "build", "target", and "Library" WITHOUT manifests (MUST BE IGNORED)
        let userDocs = workspace.appendingPathComponent("UserNotes", isDirectory: true)
        let unverifiedBuild = userDocs.appendingPathComponent("build", isDirectory: true)
        let unverifiedTarget = userDocs.appendingPathComponent("target", isDirectory: true)
        let unverifiedLibrary = userDocs.appendingPathComponent("Library", isDirectory: true)
        for dir in [unverifiedBuild, unverifiedTarget, unverifiedLibrary] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 8, count: 16_384).write(to: dir.appendingPathComponent("important.pdf"))
        }

        let results = try ProjectBuildScanner().scan(roots: [workspace], minimumSize: 1)
        let foundPaths = Set(results.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })

        #expect(foundPaths.contains(swiftBuild.standardizedFileURL.path))
        #expect(foundPaths.contains(rustTarget.standardizedFileURL.path))
        #expect(foundPaths.contains(nodeModules.standardizedFileURL.path))
        #expect(foundPaths.contains(nextBuild.standardizedFileURL.path))
        #expect(foundPaths.contains(cmakeApp.appendingPathComponent("build").standardizedFileURL.path))
        #expect(foundPaths.contains(pyVenv.standardizedFileURL.path))
        #expect(foundPaths.contains(customCache.standardizedFileURL.path))

        // Unverified folders must never be classified as project build output
        #expect(!foundPaths.contains(unverifiedBuild.standardizedFileURL.path))
        #expect(!foundPaths.contains(unverifiedTarget.standardizedFileURL.path))
        #expect(!foundPaths.contains(unverifiedLibrary.standardizedFileURL.path))
    }
}
