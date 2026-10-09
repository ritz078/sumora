import SwiftUI

struct FreshnessBadge: View {
    @Environment(AppDependencies.self) private var dependencies
    let quoteAt: Date?

    var body: some View {
        if let quoteAt, dependencies.demoDate.timeIntervalSince(quoteAt) > 2 * 86400 {
            Label("Price \(DisplayFormat.age(quoteAt, relativeTo: dependencies.demoDate))", systemImage: "clock")
                .font(.caption2).foregroundStyle(.orange)
        }
    }
}
