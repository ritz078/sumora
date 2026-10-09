import Foundation

enum HoldingSort: String, CaseIterable, Identifiable {
    case value = "Highest value", gain = "Highest gain", name = "Name"
    var id: Self { self }
}

struct HoldingsQuery {
    var search = ""
    var assetClass: AssetClass?
    var sort: HoldingSort = .value

    func apply(to holdings: [Holding]) -> [Holding] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return holdings.filter { holding in
            (assetClass == nil || holding.assetClass == assetClass) &&
            (term.isEmpty || [holding.name, holding.symbol, holding.accountID].contains { $0.localizedCaseInsensitiveContains(term) })
        }.sorted { left, right in
            switch sort {
            case .name: return left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .value: return descending(left.value, right.value, left: left, right: right)
            case .gain: return descending(left.gain, right.gain, left: left, right: right)
            }
        }
    }

    private func descending(_ lhs: DecimalValue?, _ rhs: DecimalValue?, left: Holding, right: Holding) -> Bool {
        switch (lhs, rhs) {
        case (.some(let a), .some(let b)) where a.value != b.value: return a.value > b.value
        case (.some, .none): return true
        case (.none, .some): return false
        default: return left.id < right.id
        }
    }
}
