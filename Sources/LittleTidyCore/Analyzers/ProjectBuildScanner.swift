import Foundation

/// Metadata describing a verified per-project build or local dependency directory.
public struct ProjectBuildClassification: Equatable, Sendable {
    public let ecosystem: String
    public let folderLabel: String
    public let reason: String
    public let confidence: Confidence
    public let recommendation: StorageRecommendation
    public let recoverability: StorageRecoverability
    public let consequence: CleanupConsequence

    public init(
        ecosystem: String,
        folderLabel: String,
        reason: String,
        confidence: Confidence = .high,
        recommendation: StorageRecommendation = .recommended,
        recoverability: StorageRecoverability = .recreatable,
        consequence: CleanupConsequence = .temporarySlowdown
    ) {
        self.ecosystem = ecosystem
        self.folderLabel = folderLabel
        self.reason = reason
        self.confidence = confidence
        self.recommendation = recommendation
        self.recoverability = recoverability
        self.consequence = consequence
    }
}

/// A discovered per-project build or local workspace cache directory on disk.
public struct ProjectBuildCandidate: Equatable, Sendable {
    public let url: URL
    public let projectURL: URL
    public let projectName: String
    public let classification: ProjectBuildClassification
    public let sizeBytes: Int64
    public let lastModified: Date?

    public var displayName: String {
        "\(projectName) · \(classification.ecosystem) (\(classification.folderLabel))"
    }

    public init(
        url: URL,
        projectURL: URL,
        projectName: String,
        classification: ProjectBuildClassification,
        sizeBytes: Int64,
        lastModified: Date?
    ) {
        self.url = url
        self.projectURL = projectURL
        self.projectName = projectName
        self.classification = classification
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }
}

/// Scans project roots for regenerable per-project build directories (`build`,
/// `.build`, `target`, `.next`, `.gradle`, `cmake-build-*`, `node_modules`,
/// `.venv`, Unity `Library`, Unreal `Intermediate`, `CACHEDIR.TAG`, etc.).
///
/// Safety invariant: A folder is NEVER classified by name alone. Every match
/// requires a sibling project manifest (such as `Package.swift`, `Cargo.toml`,
/// `package.json`, `build.gradle`, `CMakeCache.txt`, `pubspec.yaml`, etc.) or
/// a valid `CACHEDIR.TAG` signature. Symbolic links are strictly excluded.
public struct ProjectBuildScanner: Sendable {
    public static let cacheDirTagSignature = "Signature: 8a477f597d28d172789f06886806bc55"

    private let maxDepth: Int
    private let maxVisitedDirectories: Int

    public init(maxDepth: Int = 5, maxVisitedDirectories: Int = 8_000) {
        self.maxDepth = maxDepth
        self.maxVisitedDirectories = maxVisitedDirectories
    }

    /// Discovers and measures verified per-project build directories inside `roots`.
    public func scan(
        roots: [URL],
        minimumSize: Int64 = 1_000_000,
        fileManager: FileManager = .default
    ) throws -> [ProjectBuildCandidate] {
        var matched: [(url: URL, projectURL: URL, projectName: String, classification: ProjectBuildClassification)] = []
        var seenPaths: Set<String> = []
        var visitedDirectories = 0

        let uniqueRoots = Dictionary(grouping: roots, by: { $0.standardizedFileURL.path }).compactMap(\.value.first)
        for root in uniqueRoots {
            try Task.checkCancellation()
            guard !Self.isSymbolicLink(root, fileManager: fileManager) else { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // Check if the root itself is a build directory.
            if let hit = Self.classifyBuildDirectory(root, fileManager: fileManager) {
                let canonical = root.standardizedFileURL.path
                if seenPaths.insert(canonical).inserted {
                    matched.append(hit)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            for case let candidate as URL in enumerator {
                try Task.checkCancellation()
                if enumerator.level > maxDepth || visitedDirectories >= maxVisitedDirectories {
                    enumerator.skipDescendants()
                    continue
                }

                let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                if values?.isSymbolicLink == true || Self.isSymbolicLink(candidate, fileManager: fileManager) {
                    enumerator.skipDescendants()
                    continue
                }
                guard values?.isDirectory == true else { continue }
                visitedDirectories += 1

                let name = candidate.lastPathComponent
                if Self.shouldSkipTraversalInto(directoryName: name, url: candidate, values: values) {
                    enumerator.skipDescendants()
                    continue
                }

                if let hit = Self.classifyBuildDirectory(candidate, fileManager: fileManager) {
                    enumerator.skipDescendants()
                    let canonical = candidate.standardizedFileURL.path
                    if seenPaths.insert(canonical).inserted {
                        matched.append(hit)
                    }
                }
            }
        }

        guard !matched.isEmpty else { return [] }

        let measuredSizes = BatchDiskUsageMeasurer.allocatedBytes(
            for: matched.map(\.url),
            fileManager: fileManager
        )

        var results: [ProjectBuildCandidate] = []
        for entry in matched {
            try Task.checkCancellation()
            let canonical = entry.url.standardizedFileURL.path
            let size = measuredSizes[canonical] ?? BatchDiskUsageMeasurer.fallbackAllocatedSize(at: entry.url, fileManager: fileManager)
            guard size >= minimumSize else { continue }
            let lastModified = (try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            results.append(ProjectBuildCandidate(
                url: entry.url,
                projectURL: entry.projectURL,
                projectName: entry.projectName,
                classification: entry.classification,
                sizeBytes: size,
                lastModified: lastModified
            ))
        }

        return results.sorted { lhs, rhs in
            lhs.sizeBytes == rhs.sizeBytes
                ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                : lhs.sizeBytes > rhs.sizeBytes
        }
    }

    /// Fast, non-recursive $O(1)$ check determining whether `url` is a verified
    /// per-project build or dependency folder.
    public static func classifyBuildDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> (url: URL, projectURL: URL, projectName: String, classification: ProjectBuildClassification)? {
        guard !isSymbolicLink(url, fileManager: fileManager) else { return nil }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        let projectName = parent.lastPathComponent.isEmpty ? name : parent.lastPathComponent

        func hasSibling(_ siblingName: String, in dir: URL = parent) -> Bool {
            fileManager.fileExists(atPath: dir.appendingPathComponent(siblingName).path)
        }

        func hasAnySibling(_ names: [String], in dir: URL = parent) -> Bool {
            names.contains { hasSibling($0, in: dir) }
        }

        func hasSiblingWithExtension(_ extensions: Set<String>, in dir: URL = parent) -> Bool {
            guard let children = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return false }
            return children.contains { child in
                guard let ext = child.split(separator: ".").last?.lowercased() else { return false }
                return extensions.contains(ext) && child != name
            }
        }

        func hasChild(_ childPath: String) -> Bool {
            fileManager.fileExists(atPath: url.appendingPathComponent(childPath).path)
        }

        // 1. Swift Package Manager (.build)
        if name == ".build", hasSibling("Package.swift") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "SwiftPM",
                folderLabel: ".build",
                reason: "Swift Package Manager build artifacts and index for \(projectName). Rebuilt automatically on the next swift build or test."
            ))
        }

        // 2. Xcode DerivedData / local build directory
        if hasChild("info.plist"), hasChild("Build"),
           let data = try? Data(contentsOf: url.appendingPathComponent("info.plist")),
           let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
           plist["WorkspacePath"] is String {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Xcode",
                folderLabel: name,
                reason: "Local Xcode DerivedData build output for \(projectName). Rebuilt automatically on the next build."
            ))
        }

        // 3. Rust Cargo / Maven / Scala SBT (target)
        if name == "target" {
            if hasSibling("Cargo.toml") {
                return (url, parent, projectName, ProjectBuildClassification(
                    ecosystem: "Rust Cargo",
                    folderLabel: "target",
                    reason: "Rust compiled crates and incremental build cache for \(projectName). Recreated by cargo build."
                ))
            }
            if hasSibling("pom.xml") {
                return (url, parent, projectName, ProjectBuildClassification(
                    ecosystem: "Maven",
                    folderLabel: "target",
                    reason: "Maven compiled classes and packaged build artifacts for \(projectName). Recreated by mvn compile."
                ))
            }
            if hasSibling("build.sbt") {
                return (url, parent, projectName, ProjectBuildClassification(
                    ecosystem: "Scala SBT",
                    folderLabel: "target",
                    reason: "SBT compiled classes and build output for \(projectName). Recreated by sbt compile."
                ))
            }
        }

        // 4. Multi-ecosystem `build` folder (CMake, Gradle/Android, Flutter/Dart, Xcode, Python)
        if name == "build" || name.hasPrefix("cmake-build-") {
            if hasChild("CMakeCache.txt"), (hasChild("CMakeFiles") || name.hasPrefix("cmake-build-")) {
                return (url, parent, projectName, ProjectBuildClassification(
                    ecosystem: "CMake",
                    folderLabel: name,
                    reason: "CMake generated build tree and object files for \(projectName). Regenerated by CMake configure and build."
                ))
            }
            if name == "build" {
                let gradleMarkers = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
                if hasAnySibling(gradleMarkers) || hasAnySibling(gradleMarkers, in: parent.deletingLastPathComponent()) {
                    return (url, parent, projectName, ProjectBuildClassification(
                        ecosystem: "Gradle",
                        folderLabel: "build",
                        reason: "Gradle compiled classes, intermediates, and outputs for \(projectName). Rebuilt on the next Gradle task."
                    ))
                }
                if hasSibling("pubspec.yaml") {
                    return (url, parent, projectName, ProjectBuildClassification(
                        ecosystem: "Flutter / Dart",
                        folderLabel: "build",
                        reason: "Flutter and Dart build intermediates for \(projectName). Rebuilt by flutter build or run."
                    ))
                }
                if hasSiblingWithExtension(["xcodeproj", "xcworkspace"]),
                   (hasChild("Intermediates.noindex") || hasChild("Products") || hasChild("XCBuildData")) {
                    return (url, parent, projectName, ProjectBuildClassification(
                        ecosystem: "Xcode",
                        folderLabel: "build",
                        reason: "Xcode project build products and intermediates for \(projectName). Rebuilt on the next Xcode build."
                    ))
                }
                if hasAnySibling(["pyproject.toml", "setup.py"]),
                   (hasChild("lib") || hasChild("temp") || hasValidCacheDirTag(url)) {
                    return (url, parent, projectName, ProjectBuildClassification(
                        ecosystem: "Python",
                        folderLabel: "build",
                        reason: "Python wheel/package build intermediates for \(projectName)."
                    ))
                }
            }
        }

        // 5. JavaScript / TypeScript / Web Frameworks
        if name == "node_modules", hasSibling("package.json") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Node.js",
                folderLabel: "node_modules",
                reason: "Installed npm/pnpm/Yarn/Bun dependencies for \(projectName). Reinstall with your package manager before running the project.",
                confidence: .medium,
                recommendation: .review,
                recoverability: .reinstallable,
                consequence: .redownloadRequired
            ))
        }
        if name == ".next", hasAnySibling(["package.json", "next.config.js", "next.config.mjs", "next.config.ts"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Next.js",
                folderLabel: ".next",
                reason: "Next.js compilation and Turbopack/Webpack cache for \(projectName). Rebuilt on next dev or next build."
            ))
        }
        if (name == ".nuxt" || name == ".output"), hasAnySibling(["nuxt.config.ts", "nuxt.config.js"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Nuxt",
                folderLabel: name,
                reason: "Nuxt generated build and bundle cache for \(projectName). Rebuilt on nuxt dev or build."
            ))
        }
        if name == ".svelte-kit", hasAnySibling(["svelte.config.js", "svelte.config.ts", "package.json"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "SvelteKit",
                folderLabel: ".svelte-kit",
                reason: "SvelteKit generated types and build cache for \(projectName)."
            ))
        }
        if name == ".astro", hasAnySibling(["astro.config.mjs", "astro.config.ts", "package.json"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Astro",
                folderLabel: ".astro",
                reason: "Astro generated types and content build cache for \(projectName)."
            ))
        }
        if name == ".turbo", hasAnySibling(["turbo.json", "package.json"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Turborepo",
                folderLabel: ".turbo",
                reason: "Turborepo local task execution cache for \(projectName)."
            ))
        }
        if name == ".parcel-cache", hasSibling("package.json") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Parcel",
                folderLabel: ".parcel-cache",
                reason: "Parcel bundler transformation cache for \(projectName)."
            ))
        }
        if name == ".vite", hasAnySibling(["package.json", "vite.config.ts", "vite.config.js", "vite.config.mjs"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Vite",
                folderLabel: ".vite",
                reason: "Vite pre-bundled dependency cache for \(projectName)."
            ))
        }
        if name == ".docusaurus", hasSibling("package.json") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Docusaurus",
                folderLabel: ".docusaurus",
                reason: "Docusaurus generated site cache for \(projectName)."
            ))
        }
        if (name == ".expo" || name == ".expo-shared"), hasSibling("package.json"), hasSibling("app.json") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Expo",
                folderLabel: name,
                reason: "Expo Metro and bundler state cache for \(projectName)."
            ))
        }
        if name == ".angular", hasSibling("angular.json"), hasChild("cache") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Angular",
                folderLabel: ".angular",
                reason: "Angular CLI persistent build cache for \(projectName)."
            ))
        }

        // 6. Python Caches & Virtual Environments
        if name == "__pycache__" {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Python",
                folderLabel: "__pycache__",
                reason: "Python compiled bytecode (.pyc) cache. Recreated automatically by Python."
            ))
        }
        let pythonToolCaches: [String: String] = [
            ".pytest_cache": "Pytest cache",
            ".mypy_cache": "Mypy type-checker cache",
            ".ruff_cache": "Ruff linter cache",
            ".hypothesis": "Hypothesis test cache",
            ".pytype": "Pytype analyzer cache"
        ]
        if let label = pythonToolCaches[name],
           (hasValidCacheDirTag(url) || hasAnySibling(["pyproject.toml", "setup.py", "requirements.txt", "pytest.ini", "tox.ini"])) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Python",
                folderLabel: name,
                reason: "\(label) for \(projectName). Recreated automatically on the next run."
            ))
        }
        if (name == ".tox" || name == ".nox"), hasAnySibling(["tox.ini", "noxfile.py", "pyproject.toml"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Python",
                folderLabel: name,
                reason: "Automated test matrix virtual environments for \(projectName)."
            ))
        }
        if (name == ".venv" || name == "venv"),
           hasChild("pyvenv.cfg"),
           hasAnySibling(["pyproject.toml", "requirements.txt", "uv.lock", "Pipfile", "setup.py"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Python",
                folderLabel: name,
                reason: "Python virtual environment for \(projectName). Recreate with uv sync or pip install.",
                confidence: .medium,
                recommendation: .review,
                recoverability: .reinstallable,
                consequence: .redownloadRequired
            ))
        }
        if name == ".ipynb_checkpoints", hasSiblingWithExtension(["ipynb"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Jupyter",
                folderLabel: ".ipynb_checkpoints",
                reason: "Jupyter Notebook checkpoint cache in \(projectName)."
            ))
        }

        // 7. Gradle / Android / Scala / Flutter project caches
        if name == ".gradle",
           hasAnySibling(["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Gradle",
                folderLabel: ".gradle",
                reason: "Project-local Gradle configuration and task cache for \(projectName)."
            ))
        }
        if (name == ".cxx" || name == ".externalNativeBuild"),
           (hasAnySibling(["build.gradle", "build.gradle.kts"]) || hasAnySibling(["build.gradle", "build.gradle.kts"], in: parent.deletingLastPathComponent())) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Android NDK",
                folderLabel: name,
                reason: "Android NDK C/C++ native build intermediates for \(projectName)."
            ))
        }
        if (name == ".bsp" || name == ".bloop" || name == ".metals"),
           hasAnySibling(["build.sbt", "pom.xml", "build.sc"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Scala",
                folderLabel: name,
                reason: "Scala build server and Metals index cache for \(projectName)."
            ))
        }
        if name == ".dart_tool", hasSibling("pubspec.yaml") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Dart / Flutter",
                folderLabel: ".dart_tool",
                reason: "Dart tool and pub resolution cache for \(projectName). Regenerated by dart/flutter pub get."
            ))
        }

        // 8. CocoaPods / Carthage / Tuist
        if name == "Pods", hasSibling("Podfile"), hasSibling("Podfile.lock") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "CocoaPods",
                folderLabel: "Pods",
                reason: "CocoaPods installed pod sources and frameworks for \(projectName). Recreate with pod install.",
                confidence: .medium,
                recommendation: .review,
                recoverability: .reinstallable,
                consequence: .redownloadRequired
            ))
        }
        if name == "Carthage", hasSibling("Cartfile"), (hasChild("Build") || hasChild("Checkouts")) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Carthage",
                folderLabel: "Carthage",
                reason: "Carthage dependency checkouts and built frameworks for \(projectName).",
                confidence: .medium,
                recommendation: .review,
                recoverability: .reinstallable,
                consequence: .redownloadRequired
            ))
        }
        if name == ".tuist-bin", hasAnySibling(["Project.swift", "Tuist.swift", "Workspace.swift"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Tuist",
                folderLabel: ".tuist-bin",
                reason: "Tuist cached binaries for \(projectName)."
            ))
        }

        // 9. Game Engines (Unity, Unreal Engine, Godot)
        if ["Library", "Temp", "Obj"].contains(name),
           hasSibling("Assets"),
           hasSibling("ProjectSettings/ProjectVersion.txt") {
            let isLibrary = name == "Library"
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Unity",
                folderLabel: name,
                reason: isLibrary
                    ? "Unity local imported asset and shader cache for \(projectName). Unity reimports assets when the project next opens."
                    : "Unity temporary build intermediates for \(projectName).",
                confidence: isLibrary ? .medium : .high,
                recommendation: isLibrary ? .review : .recommended,
                recoverability: .recreatable,
                consequence: .temporarySlowdown
            ))
        }
        if ["Intermediate", "DerivedDataCache"].contains(name),
           hasSiblingWithExtension(["uproject"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Unreal Engine",
                folderLabel: name,
                reason: "Unreal Engine shader and C++ intermediate cache for \(projectName). Regenerated on next editor launch or build."
            ))
        }
        if name == ".godot", hasSibling("project.godot") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Godot",
                folderLabel: ".godot",
                reason: "Godot 4 imported resource and shader cache for \(projectName)."
            ))
        }

        // 10. Zig, .NET, Elixir, Haskell, Bazel, Clangd, Terraform
        if (name == ".zig-cache" || name == "zig-out"), hasSibling("build.zig") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Zig",
                folderLabel: name,
                reason: "Zig compiler cache and build output for \(projectName)."
            ))
        }
        if name == "obj", hasSiblingWithExtension(["csproj", "fsproj", "vbproj"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: ".NET",
                folderLabel: "obj",
                reason: ".NET MSBuild intermediate object files for \(projectName)."
            ))
        }
        if name == "_build", hasSibling("mix.exs") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Elixir Mix",
                folderLabel: "_build",
                reason: "Elixir Mix compiled beam artifacts for \(projectName)."
            ))
        }
        if (name == ".stack-work" || name == "dist-newstyle"),
           (hasAnySibling(["stack.yaml", "cabal.project"]) || hasSiblingWithExtension(["cabal"])) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Haskell",
                folderLabel: name,
                reason: "Haskell Stack/Cabal build artifacts for \(projectName)."
            ))
        }
        if ["bazel-bin", "bazel-out", "bazel-testlogs"].contains(name),
           hasAnySibling(["MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Bazel",
                folderLabel: name,
                reason: "Bazel build output directory for \(projectName)."
            ))
        }
        if name == ".clangd", hasAnySibling(["compile_commands.json", "CMakeLists.txt", ".clangd"]) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Clangd",
                folderLabel: ".clangd",
                reason: "Clangd C/C++ language server background index for \(projectName)."
            ))
        }
        if name == ".terraform", hasSibling(".terraform.lock.hcl") {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Terraform",
                folderLabel: ".terraform",
                reason: "Terraform local provider plugin cache for \(projectName). Recreated by terraform init.",
                confidence: .medium,
                recommendation: .review,
                recoverability: .reinstallable,
                consequence: .redownloadRequired
            ))
        }

        // 11. Universal CACHEDIR.TAG specification
        if hasValidCacheDirTag(url) {
            return (url, parent, projectName, ProjectBuildClassification(
                ecosystem: "Standard Cache",
                folderLabel: name,
                reason: "Directory marked with a verified CACHEDIR.TAG signature inside \(projectName)."
            ))
        }

        return nil
    }

    /// Checks whether `<directory>/CACHEDIR.TAG` exists as a regular file and
    /// begins with the standard `Signature: 8a477f597d28d172789f06886806bc55` header.
    public static func hasValidCacheDirTag(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        let tagURL = directory.appendingPathComponent("CACHEDIR.TAG", isDirectory: false)
        guard (try? fileManager.attributesOfItem(atPath: tagURL.path)[.type] as? FileAttributeType) == .typeRegular,
              let handle = try? FileHandle(forReadingFrom: tagURL) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64) else { return false }
        let prefix = String(decoding: data, as: UTF8.self)
        return prefix.hasPrefix(cacheDirTagSignature)
    }

    private static func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func shouldSkipTraversalInto(directoryName: String, url: URL, values: URLResourceValues?) -> Bool {
        if values?.isPackage == true { return true }
        let skippedNames: Set<String> = [
            ".git", ".hg", ".svn", ".Trash", "CoreDevice",
            "Photos Library.photoslibrary"
        ]
        if skippedNames.contains(directoryName) { return true }
        let skippedExtensions: Set<String> = [
            "app", "framework", "bundle", "xcodeproj", "xcworkspace",
            "xcarchive", "photoslibrary", "musiclibrary", "vmwarevm", "pvm", "simruntime"
        ]
        if skippedExtensions.contains(url.pathExtension.lowercased()) { return true }
        // Do not walk ~/Library when scanning a home folder for projects.
        if directoryName == "Library",
           FileManager.default.fileExists(atPath: url.appendingPathComponent("Preferences").path),
           FileManager.default.fileExists(atPath: url.appendingPathComponent("Caches").path) {
            return true
        }
        return false
    }
}

/// Fast batch allocated-size measurement using `/usr/bin/du -x -sk` with a pure
/// `FileManager` fallback when `du` is unavailable or fails for a path.
public enum BatchDiskUsageMeasurer {
    public static func allocatedBytes(
        for urls: [URL],
        chunkSize: Int = 64,
        fileManager: FileManager = .default
    ) -> [String: Int64] {
        let uniqueURLs = Dictionary(grouping: urls, by: { $0.standardizedFileURL.path }).compactMap(\.value.first)
        guard !uniqueURLs.isEmpty else { return [:] }

        var allSizes: [String: Int64] = [:]
        var index = 0
        while index < uniqueURLs.count {
            if Task.isCancelled { break }
            let end = min(index + chunkSize, uniqueURLs.count)
            let chunk = Array(uniqueURLs[index..<end])
            index = end

            let process = Process()
            let stdout = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-x", "-sk"] + chunk.map(\.path)
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let fields = line.split(separator: "\t", maxSplits: 1)
                    guard fields.count == 2, let kibibytes = Int64(fields[0]), kibibytes > 0 else { continue }
                    let path = URL(fileURLWithPath: String(fields[1])).standardizedFileURL.path
                    allSizes[path] = kibibytes * 1_024
                }
            } catch {
                continue
            }
        }
        return allSizes
    }

    public static func fallbackAllocatedSize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
