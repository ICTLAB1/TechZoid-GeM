import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var selection: Tab = .vault

    enum Tab: Hashable { case vault, search, settings }

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Vault", systemImage: "lock.square.stack.fill") }
                .tag(Tab.vault)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .task { await store.sync() }
    }
}
