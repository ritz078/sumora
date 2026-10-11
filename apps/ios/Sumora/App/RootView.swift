import SwiftUI

struct RootView:View {
 @Environment(AppDependencies.self) private var dependencies
 var body:some View {
  Group {
   if dependencies.bypassLogin { MainTabView() }
   else if dependencies.auth.isValidating { ProgressView("Checking your session…") }
   else if let account=dependencies.auth.account {
    if account.onboardingCompleted { MainTabView().id(account.id) }
    else { OnboardingView().id(account.id) }
   } else { LoginView() }
  }
  .task {
   guard !dependencies.bypassLogin else {return}
   await dependencies.auth.restore()
   await dependencies.activateSession()
  }
  .onChange(of:dependencies.auth.account?.id) { _,id in
   if id != nil { Task { await dependencies.activateSession() } }
   else if !dependencies.bypassLogin {dependencies.clearPrivateState()}
  }
  .onReceive(NotificationCenter.default.publisher(for:.appSessionInvalidated).receive(on:RunLoop.main)) { notification in
   guard let token=notification.object as? String,token == dependencies.auth.sessionToken else {return}
   dependencies.auth.clearLocalSession();dependencies.clearPrivateState()
  }
 }
}

private struct LoginView:View {
 @Environment(AppDependencies.self) private var dependencies
 var body:some View {
  VStack(spacing:24) {
   Spacer()
   Image(systemName:"chart.pie.fill").font(.system(size:56)).foregroundStyle(Color.accentColor)
   VStack(spacing:12) {
    Text("Sumora").font(.largeTitle.bold())
    Text("Your wealth, in one view.").font(.title3).foregroundStyle(.secondary)
   }
   Spacer()
   if let error=dependencies.auth.errorMessage {
    Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
   }
   if dependencies.auth.sessionToken != nil {
    Button("Retry session check") {Task {await dependencies.auth.restore();await dependencies.activateSession()}}
     .buttonStyle(.borderedProminent).disabled(dependencies.auth.isBusy)
   }
   Button {Task {await dependencies.auth.signIn()}} label: {
    HStack {Text("G").font(.title3.bold());Text("Sign in with Google").font(.headline);if dependencies.auth.isBusy {ProgressView()}}
     .frame(maxWidth:.infinity).padding(.vertical,12)
   }.buttonStyle(.bordered).tint(.primary).accessibilityIdentifier("sign-in-google").disabled(dependencies.auth.isBusy)
   Text("Gmail and investment connections are added separately after you sign in.")
    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
  }.padding(28).background(Color(.systemGroupedBackground))
 }
}

private struct OnboardingView:View {
 @Environment(AppDependencies.self) private var dependencies
 var body:some View {
  NavigationStack {
   List {
    Section {
     Text("Connect the accounts you want to include, then save the passwords needed to decrypt their statements.")
      .foregroundStyle(.secondary)
     Text("You can skip providers and add them later in Settings.").font(.footnote).foregroundStyle(.secondary)
    }
    ZerodhaSetupSection()
    GmailConnectionSection()
    INDmoneyConnectionSection()
    GoldConnectionSection()
    HDFCConnectionSection()
    NPSConnectionSection()
    BondsConnectionSection()
    Section {
     if let progress=dependencies.setupProgress {ProgressView(progress)}
     if let error=dependencies.setupError ?? dependencies.auth.errorMessage {Text(error).font(.footnote).foregroundStyle(.orange)}
     Button("Fetch consolidated holdings") {Task {await dependencies.fetchConsolidatedHoldings()}}
      .font(.headline).accessibilityIdentifier("fetch-consolidated-holdings")
      .disabled(dependencies.isFetchingHoldings || dependencies.gmail.isBusy || dependencies.indmoney.isBusy || dependencies.zerodha.isConnecting || dependencies.gold.isBusy || dependencies.hdfc.isBusy || dependencies.nps.isBusy || dependencies.bonds.isBusy)
    }
   }.navigationTitle("Set up your portfolio")
    .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("Log out") {Task {await dependencies.logout()}}.disabled(dependencies.auth.isBusy)}}
    .disabled(dependencies.isFetchingHoldings)
  }
 }
}
struct ZerodhaSetupSection:View {
 @Environment(AppDependencies.self) private var dependencies
 var body:some View {
  Section("Zerodha · Indian investments") {
   if dependencies.zerodha.connected {Label("Account linked",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}
   Button(dependencies.zerodha.connected ? "Reconnect Zerodha":"Connect Zerodha") {Task {await dependencies.connectZerodha()}}
    .accessibilityIdentifier("connect-zerodha").disabled(dependencies.zerodha.isConnecting)
   if dependencies.zerodha.isConnecting {ProgressView("Opening Zerodha…")}
   if let error=dependencies.zerodha.errorMessage {Text(error).font(.footnote).foregroundStyle(.orange)}
  }.task {await dependencies.zerodha.refresh()}
 }
}
