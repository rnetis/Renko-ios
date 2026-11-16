import SwiftUI

/// Sheet listing every tradable linear USDT-M perpetual with search and a
/// favourites watchlist (swipe a row, or use the star in the main toolbar).
struct SymbolPicker: View {
    let contracts: [ContractInfo]
    let favorites: [String]
    let loadError: String?
    @Binding var selection: String
    let onToggleFavorite: (String) -> Void
    let onReload: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ContractInfo] {
        guard !query.isEmpty else {
            // Favourites float to the top while not searching.
            let favs = Set(favorites)
            return contracts.filter { favs.contains($0.symbol) }
                + contracts.filter { !favs.contains($0.symbol) }
        }
        return contracts.filter {
            $0.symbol.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if contracts.isEmpty {
                    notLoaded
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filtered) { contract in
                        Button {
                            selection = contract.symbol
                            dismiss()
                        } label: {
                            row(for: contract)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                onToggleFavorite(contract.symbol)
                            } label: {
                                Label(favorites.contains(contract.symbol) ? "Remove" : "Watch",
                                      systemImage: favorites.contains(contract.symbol) ? "star.slash" : "star")
                            }
                            .tint(Theme.accent)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search contracts")
            .navigationTitle("USDT-M Perpetuals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for contract: ContractInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contract.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Text(contract.symbol)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
            if favorites.contains(contract.symbol) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                    .accessibilityLabel("In watchlist")
            }
            if contract.symbol == selection {
                Image(systemName: "checkmark")
                    .foregroundColor(Theme.accent)
            }
        }
    }

    /// Shown while `exchangeInfo` is loading or when it failed (previously an
    /// empty list looked like "no search results").
    private var notLoaded: some View {
        VStack(spacing: 12) {
            if let loadError {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundColor(Theme.accent)
                Text(loadError)
                    .font(.footnote)
                    .foregroundColor(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry", action: onReload)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            } else {
                ProgressView()
                Text("Loading contracts…")
                    .font(.footnote)
                    .foregroundColor(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
