import SwiftUI

/// Sheet listing every tradable linear USDT-M perpetual with search.
struct SymbolPicker: View {
    let contracts: [ContractInfo]
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ContractInfo] {
        query.isEmpty
            ? contracts
            : contracts.filter { $0.symbol.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filtered) { contract in
                        Button {
                            selection = contract.symbol
                            dismiss()
                        } label: {
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
                                if contract.symbol == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
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
}
