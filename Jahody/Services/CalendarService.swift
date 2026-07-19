import Foundation

/// Kalendář z účtu uživatele (pro výběr cílového kalendáře v Nastavení).
struct CalendarInfo: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let summary: String
    var isPrimary: Bool = false
}

enum CalendarServiceError: LocalizedError {
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Neplatná odpověď z Google Kalendáře."
        case .api(let statusCode, let message):
            return "Google Kalendář (\(statusCode)): \(message)"
        }
    }
}

/// Abstrakce nad Google Calendar API. Reálná implementace `GoogleCalendarService`,
/// pro vývoj a testy bez klíčů `MockCalendarService`.
protocol CalendarService {
    /// Kalendáře, do kterých může uživatel zapisovat.
    func listCalendars() async throws -> [CalendarInfo]
    /// Vytvoří událost a vrátí její ID.
    func createEvent(for order: Order, calendarId: String) async throws -> String
    /// Aktualizuje událost podle `order.calendarEventId`.
    func updateEvent(for order: Order, eventId: String, calendarId: String) async throws
    /// Smaže událost. Neexistující událost (404/410) se nepovažuje za chybu.
    func deleteEvent(eventId: String, calendarId: String) async throws
}

// MARK: - Reálná implementace (Google Calendar API v3 přes REST)

final class GoogleCalendarService: CalendarService {
    /// Dodá čerstvý OAuth access token (AuthService.freshAccessToken).
    private let tokenProvider: () async throws -> String
    private let session: URLSession
    private static let baseURL = "https://www.googleapis.com/calendar/v3"
    private static let timeZoneID = "Europe/Prague"

    init(tokenProvider: @escaping () async throws -> String, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func listCalendars() async throws -> [CalendarInfo] {
        struct CalendarListItem: Decodable {
            let id: String
            let summary: String?
            let summaryOverride: String?
            let primary: Bool?
        }
        struct CalendarList: Decodable {
            let items: [CalendarListItem]?
        }
        let data = try await request(
            path: "users/me/calendarList",
            query: [URLQueryItem(name: "minAccessRole", value: "writer")],
            method: "GET",
            body: nil
        )
        let list = try JSONDecoder().decode(CalendarList.self, from: data)
        return (list.items ?? []).map {
            CalendarInfo(
                id: $0.id,
                summary: $0.summaryOverride ?? $0.summary ?? $0.id,
                isPrimary: $0.primary ?? false
            )
        }
    }

    func createEvent(for order: Order, calendarId: String) async throws -> String {
        struct CreatedEvent: Decodable { let id: String }
        let data = try await request(
            path: "calendars/\(encode(calendarId))/events",
            method: "POST",
            body: eventBody(for: order)
        )
        return try JSONDecoder().decode(CreatedEvent.self, from: data).id
    }

    func updateEvent(for order: Order, eventId: String, calendarId: String) async throws {
        _ = try await request(
            path: "calendars/\(encode(calendarId))/events/\(encode(eventId))",
            method: "PATCH",
            body: eventBody(for: order)
        )
    }

    func deleteEvent(eventId: String, calendarId: String) async throws {
        do {
            _ = try await request(
                path: "calendars/\(encode(calendarId))/events/\(encode(eventId))",
                method: "DELETE",
                body: nil
            )
        } catch CalendarServiceError.api(let status, _) where status == 404 || status == 410 {
            // Událost už neexistuje — cíl (žádná událost) je splněn.
        }
    }

    // MARK: Pomocné

    private func eventBody(for order: Order) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: Self.timeZoneID)
        return [
            "summary": EventComposer.title(for: order),
            "description": EventComposer.description(for: order),
            "start": [
                "dateTime": iso.string(from: order.pickupAt),
                "timeZone": Self.timeZoneID,
            ],
            "end": [
                "dateTime": iso.string(from: EventComposer.endDate(for: order)),
                "timeZone": Self.timeZoneID,
            ],
        ]
    }

    private func encode(_ pathComponent: String) -> String {
        pathComponent.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        ) ?? pathComponent
    }

    private func request(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: [String: Any]?
    ) async throws -> Data {
        // Pozor: `path` už obsahuje procentově zakódované ID kalendáře (znak @ apod.).
        // Proto NEpoužíváme appendingPathComponent (ten by ho zakódoval podruhé) a
        // sestavíme URL z řetězce, který si kódování zachová.
        var components = URLComponents(string: Self.baseURL + "/" + path)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        let token = try await tokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CalendarServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CalendarServiceError.api(
                statusCode: http.statusCode,
                message: Self.errorMessage(from: data) ?? "Neznámá chyba"
            )
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable { let message: String? }
            let error: APIError?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }
}

// MARK: - Mock pro vývoj bez klíčů a pro SwiftUI preview

/// Drží události jen v paměti a loguje do konzole. Umožňuje vyvíjet
/// a testovat celou aplikaci dřív, než jsou hotové OAuth klíče.
final class MockCalendarService: CalendarService {
    private var events: [String: String] = [:] // eventId -> title
    private let queue = DispatchQueue(label: "MockCalendarService")

    func listCalendars() async throws -> [CalendarInfo] {
        [
            CalendarInfo(id: "mock-primary", summary: "Můj kalendář (mock)", isPrimary: true),
            CalendarInfo(id: "mock-objednavky", summary: "Objednávky farma (mock)"),
        ]
    }

    func createEvent(for order: Order, calendarId: String) async throws -> String {
        let eventId = "mock-\(UUID().uuidString)"
        let title = EventComposer.title(for: order)
        queue.sync { events[eventId] = title }
        print("🗓️ [MockCalendar] create \(eventId): \(title)")
        return eventId
    }

    func updateEvent(for order: Order, eventId: String, calendarId: String) async throws {
        let title = EventComposer.title(for: order)
        queue.sync { events[eventId] = title }
        print("🗓️ [MockCalendar] update \(eventId): \(title)")
    }

    func deleteEvent(eventId: String, calendarId: String) async throws {
        _ = queue.sync { events.removeValue(forKey: eventId) }
        print("🗓️ [MockCalendar] delete \(eventId)")
    }
}
