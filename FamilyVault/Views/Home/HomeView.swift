import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var selection: Tab = .vault
    /// Set when a scan creates an entry, so the app can show it straight away.
    @State private var scannedItem: VaultItem?

    enum Tab: Hashable { case vault, search, scan, tools, settings }

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Vault", systemImage: "lock.square.stack.fill") }
                .tag(Tab.vault)

            // Search keeps its tab. Folding it into the dashboard would have
            // left the one screen you reach for when you are in a hurry
            // behind an extra tap.
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            // Scanning earns a tab of its own: it is the fastest way from a
            // piece of paper to a filled-in entry, and it was previously
            // reachable only from a card partway down the dashboard.
            QuickScanView(showsDismissButton: false, onOpenEntry: { scannedItem = $0 })
                .tabItem { Label("Scan", systemImage: "doc.viewfinder") }
                .tag(Tab.scan)

            ToolsView()
                .tabItem { Label("Tools", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.tools)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .task { await store.sync() }
        .sheet(item: $scannedItem) { item in
            NavigationStack { ItemDetailView(itemID: item.id) }
        }
    }
}
