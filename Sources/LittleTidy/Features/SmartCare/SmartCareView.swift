import AppKit
import LittleTidyCore
import SwiftUI

struct SmartCareView: View {
    @ObservedObject var store: ScanReviewStore
    let systemCare: SystemCareStore

    @State private var showTrashSheet = false
    @State private var showCleanAllSheet = false
    @State private var openTrashSheetAfterCleanAll = false
    @State private var openTrashSheetAfterEveryday = false

    private var cards: [SmartCareCard] {
        store.smartCareCards(startupItemCount: systemCare.startup.count)
    }

    private var hasResults: Bool {
        store.hasCompletedScan || store.isScanning || !store.developerStorageInventory.items.isEmpty
    }

    private var isBusy: Bool {
        store.isScanning || store.isScanningDeveloperStorage || store.isCleaningDeveloperStorage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.isScanning { scanProgress }
                if hasResults {
                    let cards = cards
                    summaryPanel(cards)
                    ForEach(SmartCareGroup.allCases) { group in
                        groupSection(group, cards: cards.filter { $0.cardID.group == group }, all: cards)
                    }
                } else {
                    preScan
                }
            }
            .padding(24)
        }
        .navigationTitle("Smart Care")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { scanButton }
        }
        .sheet(isPresented: $showTrashSheet) {
            TrashEmptySheet(store: store, isPresented: $showTrashSheet)
        }
        .sheet(isPresented: $showCleanAllSheet, onDismiss: {
            store.dismissCleanAllSafe()
            if openTrashSheetAfterCleanAll {
                openTrashSheetAfterCleanAll = false
                showTrashSheet = true
            }
        }) {
            CleanAllSafeSheet(store: store, isPresented: $showCleanAllSheet) {
                openTrashSheetAfterCleanAll = true
                showCleanAllSheet = false
            }
        }
        .sheet(item: $store.everydayReviewKind, onDismiss: {
            if openTrashSheetAfterEveryday {
                openTrashSheetAfterEveryday = false
                showTrashSheet = true
            }
        }) { kind in
            EverydayReviewSheet(kind: kind, store: store) {
                openTrashSheetAfterEveryday = true
                store.dismissEverydayReview()
            }
        }
        .sheet(isPresented: $store.showPermissionGuide, onDismiss: { store.recheckPermissions() }) {
            PermissionGuideSheet(store: store)
        }
        .onAppear {
            if store.trashPreview == nil && !store.trashNeedsAccess { store.refreshTrashPreview() }
            store.presentPermissionGuideIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.recheckPermissions()
        }
        .onChange(of: store.scanRoots) { _, _ in
            // A newly approved Downloads folder shows up without pressing Scan.
            if hasResults { store.scanEverydaySpace() }
        }
    }

    // MARK: - Toolbar

    private var subtitle: String {
        // Until the developer scan has produced something, its date is not a
        // real "last scanned" time.
        guard hasResults, !store.isScanning, store.hasCompletedScan,
              !store.isScanningDeveloperStorage, !store.developerStorageInventory.items.isEmpty else { return "" }
        let date = store.developerStorageInventory.scannedAt
        return "Scanned \(date.formatted(.relative(presentation: .named)))"
    }

    private var scanButton: some View {
        Button {
            if store.isScanning {
                store.startOrCancelScan()
            } else {
                store.startSmartCareScan()
                if !systemCare.isScanning { systemCare.scan() }
            }
        } label: {
            Label(store.isScanning ? "Cancel" : (hasResults ? "Scan Again" : "Scan"),
                  systemImage: store.isScanning ? "xmark.circle" : (hasResults ? "arrow.clockwise" : "sparkle.magnifyingglass"))
                .labelStyle(.titleAndIcon)
        }
        .keyboardShortcut("r", modifiers: [.command])
    }

    // MARK: - Scanning and empty state

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(store.currentScanLocation.map { "Reading \($0)" } ?? store.statusMessage)
                    .font(.callout)
                    .foregroundStyle(Color.cleanerSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ProgressView(value: store.progress)
            Text("Nothing is removed during a scan.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
        }
        .padding(16)
        .cleanerInteractiveSurface(cornerRadius: 12)
    }

    private var preScan: some View {
        VStack(spacing: 14) {
            SmartCareTile(symbol: "sparkles", tint: Color.accentColor, fill: Color.accentColor.opacity(0.14), size: 56)
            Text("Check your Mac").font(.title2.weight(.semibold))
            Text("One scan reads caches, developer data, AI tools, the Trash, apps and snapshots. Nothing is removed until you confirm.")
                .font(.callout)
                .foregroundStyle(Color.cleanerSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                store.startSmartCareScan()
                if !systemCare.isScanning { systemCare.scan() }
            } label: {
                Label("Scan", systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Summary panel

    private func summaryPanel(_ cards: [SmartCareCard]) -> some View {
        let headline = SmartCareBuilder.headline(for: cards)
        let candidate = store.cleanAllCandidate
        let trashBytes = candidate.items.filter { !$0.isIrreversibleCleanup }.reduce(Int64(0)) { $0 + $1.bytes }
        let permanentBytes = candidate.irreversibleItems.reduce(Int64(0)) { $0 + $1.bytes }
        let trashCard = cards.first { $0.cardID == .trash }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                safeBlock(headline, candidate: candidate, trashBytes: trashBytes, permanentBytes: permanentBytes)
                Divider()
                reviewBlock(headline)
            }
            .cleanerInteractiveSurface(cornerRadius: 14)

            if let trashCard, trashCard.entries.count > 0 {
                Label("The Trash (\(ByteCountFormatter.cleanerString(from: trashCard.reviewBytes + trashCard.recommendedBytes))) is not counted in either total.",
                      systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.cleanerSecondaryText)
            }
        }
    }

    private func safeBlock(_ headline: SmartCareHeadline, candidate: SmartCareCleanPlan, trashBytes: Int64, permanentBytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SmartCareTile(symbol: "checkmark.shield", tint: Color.cleanerSuccessText, fill: Color.cleanerSuccess.opacity(0.18), size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    if store.isScanningDeveloperStorage {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Scanning…").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.cleanerSecondaryText)
                        }
                        .frame(height: 40, alignment: .leading)
                    } else {
                        SmartCareNumber(bytes: headline.safeBytes, size: 34)
                    }
                    Text("you can clean safely").font(.body.weight(.medium))
                }
            }
            Text("Recommended items only. Most are rebuilt by the tools that made them.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)

            Button {
                store.prepareCleanAllSafe()
                showCleanAllSheet = store.cleanAllPlan != nil
            } label: {
                HStack(spacing: 6) {
                    if candidate.hasIrreversibleItems { Image(systemName: "exclamationmark.triangle.fill") }
                    Text(candidate.isEmpty ? "Nothing safe to clean" : "Clean \(ByteCountFormatter.cleanerString(from: candidate.totalBytes)) Safely…")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!store.canCleanAllSafe)
            .accessibilityLabel(candidate.isEmpty ? "Nothing safe to clean" : "Clean \(ByteCountFormatter.cleanerString(from: candidate.totalBytes)) safely")

            if !candidate.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    reversibilityBar(trash: trashBytes, permanent: permanentBytes)
                    if trashBytes > 0 {
                        Label("\(ByteCountFormatter.cleanerString(from: trashBytes)) goes to the Trash and can be restored.",
                              systemImage: "arrow.uturn.backward")
                    }
                    if permanentBytes > 0 {
                        Label("\(ByteCountFormatter.cleanerString(from: permanentBytes)) is removed for good.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.cleanerDangerText)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reversibilityBar(trash: Int64, permanent: Int64) -> some View {
        GeometryReader { proxy in
            let total = Double(max(trash + permanent, 1))
            HStack(spacing: 2) {
                if trash > 0 {
                    Rectangle().fill(Color.cleanerSuccess.opacity(0.45))
                        .frame(width: max(2, proxy.size.width * Double(trash) / total))
                }
                if permanent > 0 {
                    Rectangle().fill(Color.cleanerDanger)
                        .frame(width: max(2, proxy.size.width * Double(permanent) / total))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func reviewBlock(_ headline: SmartCareHeadline) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SmartCareTile(symbol: "eye", tint: Color.cleanerInfoText, fill: Color.cleanerInfo.opacity(0.18), size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    SmartCareNumber(bytes: headline.reviewBytes, size: 34)
                    Text("to review first").font(.body.weight(.medium))
                }
            }
            Text("You decide item by item. Open Review on a card.")
                .font(.subheadline)
                .foregroundStyle(Color.cleanerSecondaryText)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Groups

    private func groupSection(_ group: SmartCareGroup, cards: [SmartCareCard], all: [SmartCareCard]) -> some View {
        let trash = cards.first { $0.cardID == .trash }
        let regular = cards.filter { $0.cardID != .trash }
        let active = regular.filter { !$0.isEmpty }
        let empty = regular.filter(\.isEmpty)
        let largest = max(all.filter { $0.cardID != .trash }.map { $0.recommendedBytes + $0.reviewBytes + $0.protectedBytes }.max() ?? 1, 1)
        let candidate = store.cleanAllCandidate

        return VStack(alignment: .leading, spacing: 12) {
            Text(group.title).font(.title3.weight(.semibold))
            if !active.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(active) { card in
                        SmartCareCardView(
                            card: card,
                            largestTotal: largest,
                            leftOutCount: card.leftOutCount,
                            leftOutBytes: card.leftOutBytes,
                            permanentBytes: card.cardID == .developer || card.cardID == .aiTools
                                ? candidate.irreversibleItems
                                    .filter { SmartCareCleanPlanner.cardID(for: $0) == card.cardID }
                                    .reduce(Int64(0)) { $0 + $1.bytes }
                                : 0,
                            isBusy: isBusy,
                            review: { store.reviewSmartCare(card) },
                            clean: { store.prepareSmartCareClean(card) },
                            allowAccess: { store.showPermissionGuide = true },
                            chooseFolder: { store.chooseFolders() }
                        )
                    }
                }
            }
            if let trash {
                SmartCareTrashRow(
                    card: trash,
                    isBusy: store.isCleaningDeveloperStorage,
                    open: { store.openTrash() },
                    empty: { showTrashSheet = true },
                    allowAccess: { store.showPermissionGuide = true }
                )
            }
            if !empty.isEmpty {
                collapsedLine(empty)
            }
        }
    }

    private func collapsedLine(_ empty: [SmartCareCard]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle").foregroundStyle(.tertiary)
            Text("Nothing to clean in").foregroundStyle(Color.cleanerSecondaryText)
            ForEach(Array(empty.enumerated()), id: \.element.cardID) { index, card in
                Button(card.cardID.title + (index < empty.count - 1 ? "," : ".")) { store.reviewSmartCare(card) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.callout)
    }
}
