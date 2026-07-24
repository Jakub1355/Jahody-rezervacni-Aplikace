import SwiftUI
import UIKit

/// Přehled objednávek po dnech (Dnes / Zítra / další dny) se součty kg jahod
/// v hlavičce každého dne — podle toho se plánuje sběr.
struct OrdersOverviewView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var orders: OrderStore
    @State private var orderToDelete: Order?

    var body: some View {
        NavigationStack {
            Group {
                let groups = DailySummary.groupByDay(orders.activeUpcomingOrders)
                if groups.isEmpty {
                    ContentUnavailableView(
                        "Žádné objednávky",
                        systemImage: "basket",
                        description: Text("Nové objednávky přibudou na záložce Nová.")
                    )
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.orders) { order in
                                    NavigationLink(value: order.id) {
                                        OrderRowView(order: order)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            markPickedUp(order)
                                        } label: {
                                            Label("Vyzvednuto", systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            orderToDelete = order
                                        } label: {
                                            Label("Smazat", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                DayHeaderView(group: group)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Objednávky")
            .navigationDestination(for: String.self) { orderId in
                OrderDetailView(orderId: orderId)
            }
            .confirmationDialog(
                "Smazat objednávku?",
                isPresented: Binding(
                    get: { orderToDelete != nil },
                    set: { if !$0 { orderToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Smazat", role: .destructive) {
                    if let order = orderToDelete { deleteOrder(order) }
                    orderToDelete = nil
                }
                Button("Zpět", role: .cancel) { orderToDelete = nil }
            } message: {
                if let order = orderToDelete {
                    Text("Objednávka \(order.customerName) se úplně smaže a odstraní se i z kalendáře.")
                }
            }
            .toolbar {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Historie", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private func deleteOrder(_ order: Order) {
        // Nejdřív smazat událost v kalendáři, pak objednávku z Firestore.
        Task { await app.calendarSync.deleteEvent(for: order) }
        orders.delete(order)
    }

    /// Označí objednávku jako vyzvednutou — přesune se do Historie.
    private func markPickedUp(_ order: Order) {
        guard let email = auth.user?.email else { return }
        try? orders.markPickedUp(order, editedBy: email)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Hlavička dne: „Dnes · čtvrtek 23. 7.“ + součet kg jahod (a dalších položek).
struct DayHeaderView: View {
    let group: DailySummary.DayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(headerTitle)
                Spacer()
                if group.strawberryKg > 0 {
                    ProductBadge(
                        iconName: "ic_jahody",
                        text: "\(CzechFormat.quantity(group.strawberryKg)) kg",
                        iconSize: 30
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
                }
            }
            let totals = DailySummary.strawberryPackageTotals(group.orders)
                + DailySummary.otherItemTotals(group.orders)
            if !totals.isEmpty {
                FlowLayout(spacing: 12) {
                    ForEach(totals, id: \.name) { total in
                        ProductBadge(
                            iconName: ProductIcon.assetName(for: total.name),
                            text: DailySummary.quantityLabel(quantity: total.quantity, unit: total.unit, size: total.size),
                            iconSize: 26
                        )
                    }
                }
                .font(.footnote)
                .textCase(nil)
            }
        }
    }

    private var headerTitle: String {
        let relative = CzechFormat.relativeDayLabel(for: group.day)
        let full = CzechFormat.dayFormatter.string(from: group.day)
        return relative == full ? full : "\(relative) · \(full)"
    }
}

/// Řádek objednávky: čas, jméno, položky zkráceně, indikátor synchronizace.
/// V hlavním přehledu jsou to jen aktivní objednávky; v Historii i zrušené/vyzvednuté.
struct OrderRowView: View {
    let order: Order

    /// Dnes je den vyzvednutí a objednávka ještě čeká — zvýrazní se oranžově.
    private var isDueToday: Bool {
        order.status == .aktivni && Calendar.current.isDateInToday(order.pickupAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(CzechFormat.timeFormatter.string(from: order.pickupAt))
                .font(.title3.bold().monospacedDigit())
                .frame(minWidth: 56, alignment: .leading)
                .foregroundStyle(isDueToday ? .orange : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(order.customerName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isDueToday ? .orange : .primary)
                    .strikethrough(order.status == .zrusena)
                FlowLayout(spacing: 12) {
                    ForEach(order.items) { item in
                        ProductBadge(
                            iconName: ProductIcon.assetName(for: item.productName),
                            text: item.quantityLabel,
                            iconSize: 30
                        )
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if order.hasPrice {
                    Text(CzechFormat.price(order.totalPrice))
                        .font(.footnote.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if order.status == .aktivni && order.hasMissingPrice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("U některé položky chybí cena")
                }

                switch order.status {
                case .zrusena:
                    Text("zrušená")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .vyzvednuta:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Vyzvednuto")
                case .aktivni:
                    if order.calendarSyncStatus != .synced {
                        // „Nesynchronizováno s kalendářem“
                        Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .foregroundStyle(order.calendarSyncStatus == .error ? .red : .orange)
                            .accessibilityLabel("Nesynchronizováno s kalendářem")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(order.status == .zrusena ? 0.5 : 1)
    }
}

/// Ikonka produktu + množství (např. 🍓 3 kg) pro přehled.
struct ProductBadge: View {
    let iconName: String
    let text: String
    var iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 3) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
            Text(text)
        }
    }
}

/// Historie — starší i vyřízené objednávky po dnech (sestupně). Potažením
/// zleva doprava lze objednávku omylem vyzvednutou/zrušenou vrátit zpět
/// mezi aktivní; zprava doleva zůstává úplné smazání.
struct HistoryView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var orders: OrderStore
    @State private var orderToDelete: Order?

    var body: some View {
        Group {
            let groups = DailySummary.groupByDay(orders.historyAndResolvedOrders).reversed()
            if !orders.historyLoaded {
                ProgressView("Načítám historii…")
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "Historie je prázdná",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                List {
                    ForEach(Array(groups)) { group in
                        Section {
                            ForEach(group.orders) { order in
                                NavigationLink(value: order.id) {
                                    OrderRowView(order: order)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        restoreOrder(order)
                                    } label: {
                                        Label("Vrátit zpět", systemImage: "arrow.uturn.backward.circle.fill")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        orderToDelete = order
                                    } label: {
                                        Label("Smazat", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(CzechFormat.dayWithYearFormatter.string(from: group.day))
                                Spacer()
                                if group.strawberryKg > 0 {
                                    ProductBadge(
                                        iconName: "ic_jahody",
                                        text: "\(CzechFormat.quantity(group.strawberryKg)) kg",
                                        iconSize: 26
                                    )
                                    .font(.subheadline.bold())
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Historie")
        .task {
            await orders.loadHistory()
        }
        .confirmationDialog(
            "Smazat objednávku?",
            isPresented: Binding(
                get: { orderToDelete != nil },
                set: { if !$0 { orderToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Smazat", role: .destructive) {
                if let order = orderToDelete { deleteOrder(order) }
                orderToDelete = nil
            }
            Button("Zpět", role: .cancel) { orderToDelete = nil }
        } message: {
            if let order = orderToDelete {
                Text("Objednávka \(order.customerName) se úplně smaže a odstraní se i z kalendáře.")
            }
        }
    }

    /// Vrátí objednávku zpět mezi aktivní — zmizí z Historie, objeví se v Objednávkách.
    private func restoreOrder(_ order: Order) {
        guard let email = auth.user?.email else { return }
        try? orders.restoreToActive(order, editedBy: email)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func deleteOrder(_ order: Order) {
        Task { await app.calendarSync.deleteEvent(for: order) }
        orders.delete(order)
    }
}
