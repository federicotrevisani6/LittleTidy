import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var enableTrashWatcher: Bool
    @State private var notificationStatus: String = "Verifica in corso..."
    private let preferencesStore: ScanPreferencesStore

    init(preferencesStore: ScanPreferencesStore = .shared) {
        self.preferencesStore = preferencesStore
        let loaded = preferencesStore.load()
        _enableTrashWatcher = State(initialValue: loaded.enableTrashWatcher)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Monitora Cestino per disinstallazioni app", isOn: $enableTrashWatcher)
                        .onChange(of: enableTrashWatcher) { _, newValue in
                            var prefs = preferencesStore.load()
                            prefs.enableTrashWatcher = newValue
                            preferencesStore.save(prefs)
                            if newValue {
                                AppUninstallNotificationManager.shared.requestAuthorizationIfNeeded()
                            }
                        }

                    Text("Quando sposti un'applicazione nel Cestino, LittleTidy cerca i file residui in ~/Library (Application Support, Caches, Preferences, Containers) e ti invia una notifica per rimuoverli.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.secondary)
                        Text("Notifiche macOS: \(notificationStatus)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Autorizza Notifiche") {
                            AppUninstallNotificationManager.shared.requestAuthorizationIfNeeded()
                            checkNotificationStatus()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Disinstallazione App & Residui", systemImage: "trash.badge.sparkle")
            }

            Section {
                Text("Le preferenze avanzate di scansione (duplicati, file grandi, cartelle di sistema e cache) possono essere personalizzate direttamente dalla schermata principale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Scansione Disco", systemImage: "internaldrive")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 260)
        .onAppear {
            checkNotificationStatus()
        }
    }

    private func checkNotificationStatus() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized:
                notificationStatus = "Abilitate"
            case .denied:
                notificationStatus = "Disabilitate nelle Impostazioni di Sistema"
            case .notDetermined:
                notificationStatus = "Non richieste"
            case .provisional:
                notificationStatus = "Provvisorie"
            @unknown default:
                notificationStatus = "Sconosciuto"
            }
        }
    }
}
