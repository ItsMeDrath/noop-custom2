import SwiftUI
import WHOOPCore

struct HealthImportView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthDataModel
    @State private var days = 14
    @State private var importTask: Task<Void, Never>?
    @State private var pendingDays: [DailySnapshot] = []
    @State private var saveError: String?
    @State private var savedMessage: String?

    var body: some View {
        SheetScaffold(title: "APPLE HEALTH") {
            VStack(alignment: .leading, spacing: 20) {
                WCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "heart.text.clipboard.fill")
                            .font(.system(size: 30)).foregroundStyle(WColor.green)
                        Text("Your health, together.").font(WFont.number(29, bold: true)).foregroundStyle(.white)
                        Text("Bring measurements from Apple Health into your daily overview. You choose what to share, and this app never writes to Apple Health.")
                            .font(WFont.body(16)).foregroundStyle(WColor.muted)
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 15) {
                        SectionHeading(title: "Choose your days", subtitle: "Today so far and your recent days")
                        Picker("Date range", selection: $days) {
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .disabled(health.isLoading || !pendingDays.isEmpty)
                        Text("Includes steps, active energy, resting heart rate, respiratory rate, heart rate, and time asleep when available.")
                            .font(WFont.body(15)).foregroundStyle(WColor.muted)
                        Text("Days run midnight to midnight UTC. Sleep is split across those days, so totals can differ from a night shown in Apple Health.")
                            .font(WFont.body(14)).foregroundStyle(WColor.muted)
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "Measurements, in context")
                        Text("Recovery, Sleep Performance, Strain, and sleep need are not provided by this import. They stay unavailable unless supplied in your day data.")
                        Text("Apple Health’s HRV uses SDNN. WHOOP’s HRV uses RMSSD. These are different measurements, so HRV isn’t included in this import.")
                        Text("Only readable days are saved. Importing updates available measurements on matching days. You can export or delete saved data from Your Data Files.")
                    }
                    .font(WFont.body(15)).foregroundStyle(WColor.muted)
                }
                if !health.isAvailable {
                    EmptyCard(symbol: "heart.slash", title: "Apple Health unavailable",
                              detail: "Open this app on an iPhone with Apple Health to import your measurements.")
                }
                if health.isLoading {
                    HStack(spacing: 12) {
                        ProgressView().tint(WColor.green)
                        Text(health.status).font(WFont.body(15)).foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(health.status).font(WFont.body(14)).foregroundStyle(WColor.muted)
                        .accessibilityIdentifier("healthImportStatus")
                }
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(WFont.body(15)).foregroundStyle(WColor.green)
                }
                if let message = saveError ?? health.error {
                    WCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(saveError == nil ? "Couldn’t import measurements" : "Couldn’t save measurements")
                                .font(WFont.label(13)).foregroundStyle(WColor.yellow)
                            Text(message).font(WFont.body(15)).foregroundStyle(.white)
                        }
                    }
                    .accessibilityIdentifier("healthImportError")
                }
                if !pendingDays.isEmpty {
                    Button("RETRY SAVING") { savePendingDays() }.buttonStyle(WButton())
                    Button("DISCARD UNSAVED IMPORT") {
                        pendingDays = []
                        saveError = nil
                    }.buttonStyle(WButton(filled: false))
                } else if health.isLoading {
                    Button("CANCEL IMPORT") { importTask?.cancel() }.buttonStyle(WButton(filled: false))
                } else {
                    Button(health.error == nil ? "IMPORT FROM APPLE HEALTH" : "TRY IMPORT AGAIN") { beginImport() }
                        .buttonStyle(WButton())
                        .disabled(!health.isAvailable)
                        .opacity(health.isAvailable ? 1 : 0.45)
                        .accessibilityIdentifier("healthImportButton")
                }
                Text("Apple Health asks for access when you tap Import. If no measurements appear, check this app’s access in Apple Health. For privacy, Apple does not tell apps whether read access was denied.")
                    .font(WFont.body(13)).foregroundStyle(WColor.muted)
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private func beginImport() {
        savedMessage = nil
        saveError = nil
        importTask = Task { @MainActor in
            do {
                let measurements = try await health.fetch(days: days)
                try Task.checkCancellation()
                pendingDays = measurements
                savePendingDays()
            } catch {
                // HealthDataModel publishes actionable query/no-data errors.
                // Cancellation leaves existing saved measurements untouched.
            }
        }
    }

    private func savePendingDays() {
        do {
            try store.mergeMeasurements(pendingDays)
            savedMessage = "Saved measurements for \(pendingDays.count) \(pendingDays.count == 1 ? "day" : "days")."
            pendingDays = []
            saveError = nil
        } catch {
            saveError = "\(error.localizedDescription) Your import is ready to save. Tap Retry Saving to try again."
        }
    }
}
