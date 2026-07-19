import Foundation
import FirebaseFirestore

/// Návrh zákazníka pro našeptávání (odvozeno z historie objednávek).
struct CustomerSuggestion: Identifiable, Hashable {
    let name: String
    let phone: String?

    var id: String { name.lowercased() }
}

/// Práce s kolekcí `orders` ve Firestore. Zápisy jsou „offline-first“:
/// neblokují UI a Firestore je po obnovení připojení samo doručí na server.
@MainActor
final class OrderStore: ObservableObject {
    /// Objednávky od začátku dneška dál (živý listener).
    @Published private(set) var upcomingOrders: [Order] = []
    /// Starší objednávky (načítané na vyžádání pro Historii a našeptávání).
    @Published private(set) var historyOrders: [Order] = []
    @Published private(set) var historyLoaded = false
    /// Firestore Security Rules zamítly přístup → účet není v `allowedUsers`.
    @Published private(set) var accessDenied = false
    @Published private(set) var listenerError: String?

    private var listener: ListenerRegistration?

    private var ordersCollection: CollectionReference {
        Firestore.firestore().collection("orders")
    }

    func start() {
        guard listener == nil else { return }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        listener = ordersCollection
            .whereField("pickupAt", isGreaterThanOrEqualTo: Timestamp(date: startOfToday))
            .order(by: "pickupAt")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == FirestoreErrorDomain,
                           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                            self.accessDenied = true
                        } else {
                            self.listenerError = error.localizedDescription
                        }
                        return
                    }
                    guard let snapshot else { return }
                    self.accessDenied = false
                    self.listenerError = nil
                    self.upcomingOrders = snapshot.documents.compactMap(Self.decodeOrder)
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        upcomingOrders = []
        historyOrders = []
        historyLoaded = false
        accessDenied = false
    }

    private static func decodeOrder(_ document: QueryDocumentSnapshot) -> Order? {
        guard var order = try? document.data(as: Order.self) else { return nil }
        order.id = document.documentID
        return order
    }

    // MARK: - Zápisy

    /// Uloží novou objednávku. Zápis projde okamžitě i offline —
    /// listener ji hned vrátí z lokální cache.
    func add(_ order: Order) throws {
        try ordersCollection.document(order.id).setData(from: order)
    }

    /// Uloží upravenou objednávku a označí ji k synchronizaci s kalendářem.
    func update(_ order: Order, editedBy email: String) throws {
        var updated = order
        updated.updatedAt = Date()
        updated.updatedBy = email
        updated.calendarSyncStatus = .pending
        try ordersCollection.document(updated.id).setData(from: updated)
    }

    /// Zruší objednávku (status `zrusena`); smazání události v kalendáři
    /// zajistí CalendarSyncManager.
    func cancel(_ order: Order, editedBy email: String) throws {
        var cancelled = order
        cancelled.status = .zrusena
        try update(cancelled, editedBy: email)
    }

    /// Zapíše výsledek synchronizace s kalendářem (nemění updatedAt).
    func markCalendarSync(orderId: String, eventId: String?, status: CalendarSyncStatus) {
        // Když událost už neexistuje (zrušená objednávka), pole se z dokumentu odstraní.
        let eventValue: Any = eventId.map { $0 as Any } ?? FieldValue.delete()
        ordersCollection.document(orderId).updateData([
            "calendarEventId": eventValue,
            "calendarSyncStatus": status.rawValue,
        ])
        // Lokální kopie se aktualizuje přes listener.
    }

    // MARK: - Historie

    /// Načte starší objednávky (pro Historii a našeptávání jmen).
    func loadHistory(limit: Int = 300) async {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        do {
            let snapshot = try await ordersCollection
                .whereField("pickupAt", isLessThan: Timestamp(date: startOfToday))
                .order(by: "pickupAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            historyOrders = snapshot.documents.compactMap(Self.decodeOrder)
            historyLoaded = true
        } catch {
            // Offline bez cache → historie prostě zůstane prázdná.
        }
    }

    // MARK: - Našeptávání

    /// Návrhy zákazníků podle zadaného textu (bez diakritiky, od nejnovějších).
    /// Výběrem se doplní i telefon.
    func customerSuggestions(matching text: String, limit: Int = 5) -> [CustomerSuggestion] {
        let query = text.folded
        guard !query.isEmpty else { return [] }

        let all = (upcomingOrders + historyOrders).sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var result: [CustomerSuggestion] = []
        for order in all {
            let key = order.customerName.folded
            guard !key.isEmpty, !seen.contains(key), key.contains(query) else { continue }
            seen.insert(key)
            let phone = order.phone?.trimmingCharacters(in: .whitespaces)
            result.append(CustomerSuggestion(name: order.customerName, phone: (phone?.isEmpty == false) ? phone : nil))
            if result.count >= limit { break }
        }
        return result
    }

    /// Telefon k přesně zadanému jménu zákazníka (z nejnovější objednávky).
    /// Slouží k automatickému doplnění telefonu při psaní jména.
    func phone(forCustomerName name: String) -> String? {
        let query = name.folded
        guard !query.isEmpty else { return nil }
        let all = (upcomingOrders + historyOrders).sorted { $0.createdAt > $1.createdAt }
        for order in all where order.customerName.folded == query {
            if let phone = order.phone?.trimmingCharacters(in: .whitespaces), !phone.isEmpty {
                return phone
            }
        }
        return nil
    }

    // MARK: - Synchronizace s kalendářem

    /// Objednávky čekající na propsání do kalendáře, které má řešit toto
    /// zařízení (naposledy je měnil přihlášený uživatel).
    /// Jen stav `pending` — objednávky se stavem `error` už automaticky
    /// neopakujeme (šlo by o nekonečné pokusy), ty jdou znovu ručně z detailu.
    func pendingCalendarOrders(for email: String) -> [Order] {
        upcomingOrders.filter {
            $0.calendarSyncStatus == .pending && ($0.updatedBy ?? $0.createdBy) == email
        }
    }
}

private extension String {
    /// Bez diakritiky a velikosti písmen — pro porovnávání jmen.
    var folded: String {
        trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: CzechFormat.locale)
            .lowercased()
    }
}
