import SwiftUI
import ContactsUI

/// Nativní výběr kontaktu (bez nutnosti oprávnění — běží mimo aplikaci).
/// Po výběru vrátí jméno a první telefonní číslo.
struct ContactPicker: UIViewControllerRepresentable {
    /// (jméno, telefon?) vybraného kontaktu.
    let onPick: (String, String?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Nabízet jen kontakty s telefonním číslem.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String?) -> Void

        init(onPick: @escaping (String, String?) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let finalName = name.isEmpty ? contact.organizationName : name
            let phone = contact.phoneNumbers.first?.value.stringValue
            onPick(finalName, phone)
        }
    }
}
