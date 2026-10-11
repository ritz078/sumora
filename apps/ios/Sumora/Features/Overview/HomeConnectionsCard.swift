import SwiftUI

struct HomeConnectionsCard: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(PortfolioStore.self) private var store
 let snapshot: PortfolioSnapshot
 private var rows: [Connection] {
  var connections = snapshot.connections
  if dependencies.isLivePortfolio {
   let gmail = dependencies.gmail.status
   let statementIDs: Set<String> = ["gullak", "hdfc", "nps", "bonds"]
   let statementAttention = connections.contains { statementIDs.contains($0.id) && $0.status == .attention }
   connections.removeAll { statementIDs.contains($0.id) || $0.id == "properties" || $0.id == "gmail" }
   connections.insert(Connection(id: "gmail", name: "Email CAS Parser", symbol: "envelope.fill", status: gmail?.connected == true ? (gmail?.error == nil && !statementAttention ? .connected : .attention) : .disconnected,
    lastSyncAt: gmail?.lastSyncAt.map { Date(timeIntervalSince1970: $0 / 1000) }, description: statementAttention ? "Investment statements need attention" : gmail?.connected == true ? "Gold, fixed deposits, NPS & bond statements" : "Connect Gmail for investment statements"), at: min(1, connections.count))
  }
  return connections
 }
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   HStack(alignment: .top) {
    VStack(alignment: .leading, spacing: 3) {
     Text("Connected Accounts").font(.appFont(.headline, weight: .bold, size: 17)).tracking(-0.425)
     Text("Auto-sync feeds & portfolio integrations").font(.appFont(.caption, size: 12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength: 4)
    Text("\(rows.filter { $0.status != .disconnected }.count) Linked").font(.appFont(.caption2, weight: .semibold, size: 11)).foregroundStyle(HomeStyle.emerald)
     .padding(.horizontal, 8).padding(.vertical, 4).background(HomeStyle.emerald.opacity(0.08), in: Capsule()).fixedSize()
   }
   VStack(spacing: 0) {
    ForEach(rows) { connection in
     HStack(spacing: 12) {
      NavigationLink { ConnectionsView().toolbar(.visible, for: .navigationBar) } label: {
       HStack(spacing: 12) {
        providerIcon(connection)
        VStack(alignment: .leading, spacing: 4) {
         HStack(spacing: 6) {
          Text(connection.name).font(.appFont(.caption, weight: .semibold, size: 13)).lineLimit(1).truncationMode(.tail)
          Text(connection.status == .connected ? "Active" : connection.status == .attention ? "Action needed" : "Not linked")
           .font(.appFont(.caption2, weight: .medium, size: 9)).foregroundStyle(color(connection)).padding(.horizontal, 5).padding(.vertical, 2)
           .background(color(connection).opacity(0.08), in: RoundedRectangle(cornerRadius: 4)).fixedSize()
         }
         Text(connection.description).font(.appFont(.caption2, size: 11)).foregroundStyle(HomeStyle.secondary).lineLimit(1).truncationMode(.tail)
        }.frame(maxWidth: .infinity, alignment: .leading)
       }
      }.buttonStyle(.plain)
      Button { Task { await refresh(connection) } } label: {
       Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12)).foregroundStyle(HomeStyle.secondary)
        .frame(width: 28, height: 28).background(HomeStyle.card, in: Circle()).overlay(Circle().stroke(HomeStyle.border, lineWidth: 1))
      }.buttonStyle(.plain).disabled(store.isRefreshing || dependencies.gmail.isBusy).accessibilityLabel("Refresh \(connection.name)")
     }.padding(14)
     if connection.id != rows.last?.id { Rectangle().fill(HomeStyle.border).frame(height: 1) }
    }
   }.background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HomeStyle.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }.homeCard().foregroundStyle(HomeStyle.ink)
 }
 @ViewBuilder private func providerIcon(_ connection: Connection) -> some View {
  if connection.id == "zerodha" || connection.id == "indmoney" {
   Text(connection.id == "zerodha" ? "Z" : "IND").font(.appFont(.subheadline, weight: .bold, size: connection.id == "zerodha" ? 14 : 11))
    .foregroundStyle(.white).frame(width: 36, height: 36)
    .background(connection.id == "zerodha" ? Color(red: 37/255, green: 99/255, blue: 235/255) : Color(red: 5/255, green: 150/255, blue: 105/255), in: RoundedRectangle(cornerRadius: 12))
  } else {
   Image(systemName: connection.id == "gmail" ? "envelope" : connection.id == "manual" ? "square.stack.3d.up" : "building.columns").font(.system(size: 18)).foregroundStyle(HomeStyle.secondary)
    .frame(width: 36, height: 36).background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HomeStyle.border, lineWidth: 1))
  }
 }
 private func color(_ connection: Connection) -> Color {
  connection.status == .attention ? .orange : connection.status == .disconnected ? HomeStyle.secondary : connection.id == "gmail" ? HomeStyle.indigo : HomeStyle.emerald
 }
 private func refresh(_ connection: Connection) async {
  if dependencies.isLivePortfolio, connection.id == "gmail" {
   await dependencies.syncGmailDocuments()
   if let message = dependencies.gmail.errorMessage { store.presentErrorToast(message) }
  } else if dependencies.isLivePortfolio, connection.id == "indmoney" {
   dependencies.indmoney.configure(address: dependencies.zerodha.address, token: dependencies.auth.sessionToken)
   await dependencies.indmoney.sync()
   if let message = dependencies.indmoney.errorMessage { store.presentErrorToast(message) }
   await store.refresh()
  } else if dependencies.isLivePortfolio, connection.id == "zerodha", connection.status == .attention {
   await dependencies.connectZerodha()
  } else { await store.refresh() }
 }
}
