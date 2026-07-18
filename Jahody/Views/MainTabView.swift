import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NewOrderView()
                .tabItem {
                    Label("Nová", systemImage: "plus.circle.fill")
                }
            OrdersOverviewView()
                .tabItem {
                    Label("Objednávky", systemImage: "list.bullet.rectangle")
                }
            SettingsView()
                .tabItem {
                    Label("Nastavení", systemImage: "gearshape")
                }
        }
    }
}
