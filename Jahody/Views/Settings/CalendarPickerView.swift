import SwiftUI

/// Výběr cílového kalendáře ze seznamu kalendářů účtu.
/// Ukládá se `calendarId` — používá se zvláštní sdílený kalendář jen pro
/// objednávky, ne „primary“.
struct CalendarPickerView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var calendars: [CalendarInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Načítám kalendáře…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Kalendáře se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Zkusit znovu") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(calendars) { calendar in
                    Button {
                        calendarSync.selectedCalendar = calendar
                        Task { await app.calendarSync.syncPending() }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(calendar.summary)
                                    .foregroundStyle(.primary)
                                if calendar.isPrimary {
                                    Text("hlavní kalendář účtu")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if calendarSync.selectedCalendar?.id == calendar.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 40)
                    }
                }
            }
        }
        .navigationTitle("Cílový kalendář")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            calendars = try await calendarSync.service.listCalendars()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
