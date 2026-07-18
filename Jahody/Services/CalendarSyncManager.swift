import Foundation
import SwiftUI

/// Propisuje objednávky do sdíleného Google Kalendáře — asynchronně,
/// aby nikdy neblokoval uložení objednávky. Při selhání opakuje
/// s exponenciálním odstupem; po vyčerpání pokusů označí objednávku
/// stavem `error` („nesynchronizováno s kalendářem“) a zkusí to znovu
/// při dalším návratu aplikace do popředí.
@MainActor
final class CalendarSyncManager: ObservableObject {
    @Published private(set) var isSyncing = false
    /// Vybraný cílový kalendář (ukládá se `calendarId`, ne „primary“).
    @Published var selectedCalendar: CalendarInfo? {
        didSet { persistSelectedCalendar() }
    }
    /// Přepínač pro vývoj bez OAuth klíčů (Nastavení → Vývoj).
    @Published var useMockCalendar: Bool {
        didSet { UserDefaults.standard.set(useMockCalendar, forKey: Self.mockDefaultsKey) }
    }

    private let realService: CalendarService
    private let mockService = MockCalendarService()
    private unowned let orders: OrderStore
    private unowned let auth: AuthService

    private var retryTask: Task<Void, Never>?
    private var failedAttempts: [String: Int] = [:] // orderId -> pokusy
    private static let maxAttemptsBeforeError = 5
    private static let calendarDefaultsKey = "selectedCalendar"
    private static let mockDefaultsKey = "useMockCalendar"

    init(realService: CalendarService, orders: OrderStore, auth: AuthService) {
        self.realService = realService
        self.orders = orders
        self.auth = auth
        self.useMockCalendar = UserDefaults.standard.bool(forKey: Self.mockDefaultsKey)
        if let data = UserDefaults.standard.data(forKey: Self.calendarDefaultsKey),
           let calendar = try? JSONDecoder().decode(CalendarInfo.self, from: data) {
            self.selectedCalendar = calendar
        }
    }

    var service: CalendarService {
        useMockCalendar ? mockService : realService
    }

    /// Je vybraný kalendář a lze synchronizovat?
    var isConfigured: Bool { selectedCalendar != nil }

    // MARK: - Synchronizace

    /// Projde objednávky čekající na synchronizaci a propíše je do kalendáře.
    /// Volá se po uložení objednávky a při návratu aplikace do popředí.
    func syncPending() async {
        guard !isSyncing,
              let calendarId = selectedCalendar?.id,
              let email = auth.user?.email
        else { return }

        isSyncing = true
        defer { isSyncing = false }

        var anyFailure = false
        for order in orders.pendingCalendarOrders(for: email) {
            let succeeded = await sync(order, calendarId: calendarId)
            if !succeeded { anyFailure = true }
        }
        if anyFailure {
            scheduleRetry()
        }
    }

    /// Ruční opakování z detailu objednávky.
    func retry(order: Order) async {
        guard let calendarId = selectedCalendar?.id else { return }
        failedAttempts[order.id] = 0
        _ = await sync(order, calendarId: calendarId)
    }

    /// Provede pro objednávku správnou akci v kalendáři. Vrací úspěch.
    private func sync(_ order: Order, calendarId: String) async -> Bool {
        do {
            switch (order.status, order.calendarEventId) {
            case (.zrusena, let eventId?):
                try await service.deleteEvent(eventId: eventId, calendarId: calendarId)
                orders.markCalendarSync(orderId: order.id, eventId: nil, status: .synced)
            case (.zrusena, nil):
                orders.markCalendarSync(orderId: order.id, eventId: nil, status: .synced)
            case (.aktivni, let eventId?):
                try await service.updateEvent(for: order, eventId: eventId, calendarId: calendarId)
                orders.markCalendarSync(orderId: order.id, eventId: eventId, status: .synced)
            case (.aktivni, nil):
                let eventId = try await service.createEvent(for: order, calendarId: calendarId)
                orders.markCalendarSync(orderId: order.id, eventId: eventId, status: .synced)
            }
            failedAttempts[order.id] = nil
            return true
        } catch {
            let attempts = (failedAttempts[order.id] ?? 0) + 1
            failedAttempts[order.id] = attempts
            if attempts >= Self.maxAttemptsBeforeError,
               order.calendarSyncStatus != .error {
                orders.markCalendarSync(
                    orderId: order.id,
                    eventId: order.calendarEventId,
                    status: .error
                )
            }
            print("🗓️ Synchronizace kalendáře selhala (pokus \(attempts)): \(error.localizedDescription)")
            return false
        }
    }

    /// Naplánuje další pokus s exponenciálním odstupem (5 s → 10 s → … max 5 min).
    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let attempt = failedAttempts.values.max() ?? 1
        let delay = min(5 * pow(2, Double(max(attempt - 1, 0))), 300)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            await self.syncPending()
        }
    }

    private func persistSelectedCalendar() {
        if let selectedCalendar, let data = try? JSONEncoder().encode(selectedCalendar) {
            UserDefaults.standard.set(data, forKey: Self.calendarDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.calendarDefaultsKey)
        }
    }
}
