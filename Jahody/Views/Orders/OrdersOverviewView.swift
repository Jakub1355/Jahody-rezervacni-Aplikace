import SwiftUI

/// Přehled objednávek po dnech (Dnes / Zítra / další dny) se součty kg jahod
/// v hlavičce každého dne — podle toho se plánuje sběr.
struct OrdersOverviewView: View {
    @EnvironmentObject private var orders: OrderStore

    var body: some View {
        NavigationStack {
            Group {
                let groups = DailySummary.groupByDay(orders.upcomingOrders)
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
            .toolbar {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Historie", systemImage: "clock.arrow.circlepath")
                }
            }
        }
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
            let otherTotals = DailySummary.otherItemTotals(group.orders)
            if !otherTotals.isEmpty {
                HStack(spacing: 12) {
                    ForEach(otherTotals, id: \.name) { total in
                        ProductBadge(
                            iconName: ProductIcon.assetName(for: total.name),
                            text: "\(CzechFormat.quantity(total.quantity)) \(total.unit)",
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
struct OrderRowView: View {
    let order: Order

    var body: some View {
        HStack(spacing: 12) {
            Text(CzechFormat.timeFormatter.string(from: order.pickupAt))
                .font(.title3.bold().monospacedDigit())
                .frame(minWidth: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(order.customerName)
                    .font(.body.weight(.medium))
                    .strikethrough(order.status == .zrusena)
                HStack(spacing: 12) {
                    ForEach(order.items) { item in
                        ProductBadge(
                            iconName: ProductIcon.assetName(for: item.productName),
                            text: "\(CzechFormat.quantity(item.quantity)) \(item.unit)",
                            iconSize: 30
                        )
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if order.status == .zrusena {
                Text("zrušená")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if order.calendarSyncStatus != .synced {
                // „Nesynchronizováno s kalendářem“
                Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(order.calendarSyncStatus == .error ? .red : .orange)
                    .accessibilityLabel("Nesynchronizováno s kalendářem")
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

/// Historie — starší objednávky po dnech (sestupně).
struct HistoryView: View {
    @EnvironmentObject private var orders: OrderStore

    var body: some View {
        Group {
            let groups = DailySummary.groupByDay(orders.historyOrders).reversed()
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
    }
}
