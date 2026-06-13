import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scan Preferences", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text("Duplicate size, large-file threshold, hidden-file scanning, and system-folder scanning are adjusted in the main overview and saved automatically.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 420)
    }
}
