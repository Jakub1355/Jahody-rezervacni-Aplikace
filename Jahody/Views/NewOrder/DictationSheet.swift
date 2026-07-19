import SwiftUI
import UIKit

/// Nadiktování objednávky. Diktovat lze **po částech a v jakémkoliv pořadí** —
/// hodnoty se sčítají (jméno, telefon, produkty, den, čas). Tlačítko „Začít
/// znovu“ vše vymaže. Vše jde pak ještě ručně upravit ve formuláři.
struct DictationSheet: View {
    @ObservedObject var model: OrderFormModel
    /// Aktivní produkty pro rozpoznání dalších položek.
    let products: [Product]

    @StateObject private var speech = SpeechDictationService()
    @Environment(\.dismiss) private var dismiss
    /// Text z předchozích nahrávek (aktuální nahrávka je ve `speech.transcript`).
    @State private var committedTranscript = ""

    /// Celý dosud nadiktovaný text (dřívější části + probíhající nahrávka).
    private var combinedTranscript: String {
        (committedTranscript + " " + speech.transcript).trimmingCharacters(in: .whitespaces)
    }

    private var preview: DictationResult? {
        combinedTranscript.isEmpty ? nil : DictationParser.parse(combinedTranscript, products: products)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !speech.isAvailable {
                    unavailableView
                } else if speech.permissionDenied {
                    permissionDeniedView
                } else {
                    instructions
                    micButton
                    transcriptView
                    if let preview {
                        previewView(preview)
                    }
                    Spacer()
                    actionButtons
                }
            }
            .padding(20)
            .navigationTitle("Nadiktovat objednávku")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") {
                        speech.reset()
                        dismiss()
                    }
                }
            }
            .onChange(of: speech.isRecording) { wasRecording, isRecording in
                // Po dokončení nahrávky si její text „uložíme“ a připravíme se na další.
                if wasRecording && !isRecording {
                    let text = speech.transcript.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        committedTranscript = combinedTranscript
                    }
                    speech.reset()
                }
            }
        }
    }

    // MARK: Části

    private var instructions: some View {
        VStack(spacing: 6) {
            Text("Diktujte klidně po částech, v jakémkoliv pořadí — hodnoty se sčítají.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Např. „Jana Nováková, 777 123 456“ — pak znovu „tři kila jahod a deset vajec“ — pak „zítra ve tři“.")
                .font(.callout)
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var micButton: some View {
        Button {
            speech.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(speech.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 120, height: 120)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
            }
            .overlay {
                if speech.isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 8)
                        .frame(width: 140, height: 140)
                        .scaleEffect(speech.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isRecording ? "Zastavit diktování" : "Přidat diktováním")
    }

    private var transcriptView: some View {
        Group {
            if speech.isRecording {
                Text("Poslouchám…")
                    .font(.headline)
                    .foregroundStyle(.red)
            } else if combinedTranscript.isEmpty {
                Text("Klepněte na mikrofon a mluvte")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if !combinedTranscript.isEmpty {
                Text(combinedTranscript)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func previewView(_ result: DictationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rozpoznáno")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            previewRow("Jméno", result.customerName)
            previewRow("Telefon", result.phone)
            previewRow("Jahody", result.strawberryKg.map { "\(CzechFormat.quantity($0)) kg" })
            previewRow("Den", result.pickupDay.map { CzechFormat.relativeDayLabel(for: $0) })
            previewRow("Čas", result.pickupMinutes.map { String(format: "%d:%02d", $0 / 60, $0 % 60) })
            if !result.extraItems.isEmpty {
                previewRow("Další", CzechFormat.itemsSummary(result.extraItems))
            }
            previewRow("Poznámka", result.note)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func previewRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(value).fontWeight(.medium)
                Spacer()
            }
            .font(.callout)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                applyAndDismiss()
            } label: {
                Text("Použít do formuláře")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(preview == nil || speech.isRecording)

            if !combinedTranscript.isEmpty, !speech.isRecording {
                Button("Začít znovu", role: .destructive) {
                    committedTranscript = ""
                    speech.reset()
                }
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "Diktování není dostupné",
            systemImage: "mic.slash",
            description: Text("Na tomto zařízení není dostupné rozpoznávání české řeči. Objednávku vyplňte ručně.")
        )
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Chybí oprávnění", systemImage: "mic.slash")
        } description: {
            Text("Povolte mikrofon a rozpoznávání řeči v Nastavení iOS → Jahody.")
        } actions: {
            Button("Otevřít Nastavení") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Akce

    private func applyAndDismiss() {
        guard let result = preview else { return }
        model.apply(dictation: result)
        committedTranscript = ""
        speech.reset()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
