import Foundation
import Contacts

/// Našeptávání jmen a telefonů z kontaktů zařízení (podle psaného textu).
@MainActor
final class ContactsService: ObservableObject {
    @Published private(set) var accessGranted = false
    private let store = CNContactStore()

    /// Zajistí oprávnění ke kontaktům (poprvé se zeptá).
    func ensureAccess() async {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            accessGranted = (try? await store.requestAccess(for: .contacts)) ?? false
        case .denied, .restricted:
            accessGranted = false
        default:
            accessGranted = true   // authorized nebo limited
        }
    }

    /// Návrhy kontaktů, jejichž jméno odpovídá zadanému textu.
    func suggestions(matching query: String, limit: Int = 5) -> [CustomerSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard accessGranted, trimmed.count >= 2 else { return [] }

        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactPhoneNumbersKey,
        ] as [CNKeyDescriptor]

        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else {
            return []
        }

        var seen = Set<String>()
        var result: [CustomerSuggestion] = []
        for contact in contacts {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let finalName = name.isEmpty ? contact.organizationName : name
            let key = finalName.lowercased()
            guard !finalName.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(CustomerSuggestion(
                name: finalName,
                phone: contact.phoneNumbers.first?.value.stringValue
            ))
            if result.count >= limit { break }
        }
        return result
    }
}
