import Foundation
import Testing
@testable import Sumora

@Suite(.serialized) @MainActor
struct AppAuthTests {
 private let address="https://login-tests.example.com"
 private let token=String(repeating:"a",count:64)
 private var accountData:Data {Data(#"{"account":{"id":"account-one","email":"owner@example.com","onboardingCompleted":true}}"#.utf8)}
 private func client() throws ->AppAuth {
  try SessionKeychain.write(token,address:"google-login:"+address)
  let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[AuthURLProtocol.self]
  return AppAuth(address:address,session:URLSession(configuration:configuration))
 }
 @Test func restoredSessionOpensCompletedAccountAndLogoutOnlyRevokesAppSession() async throws {
  let auth=try client();defer{auth.clearLocalSession()}
  AuthURLProtocol.response=(200,accountData)
  await auth.restore()
  #expect(auth.account?.onboardingCompleted == true)
  #expect(auth.sessionToken == token)
  AuthURLProtocol.response=(200,Data(#"{"loggedOut":true}"#.utf8))
  #expect(await auth.logout())
  #expect(auth.account == nil)
  #expect(auth.sessionToken == nil)
  #expect(SessionKeychain.read("google-login:"+address) == nil)
  #expect(AuthURLProtocol.request?.url?.path == "/v1/auth/session")
  #expect(AuthURLProtocol.request?.httpMethod == "DELETE")
 }
 @Test func expiredSessionIsRemovedFromDevice() async throws {
  let auth=try client();defer{auth.clearLocalSession()}
  AuthURLProtocol.response=(401,Data(#"{"error":{"code":"SIGN_IN_REQUIRED","message":"Expired"}}"#.utf8))
  await auth.restore()
  #expect(auth.sessionToken == nil)
  #expect(auth.account == nil)
  #expect(!auth.isValidating)
 }
 @Test func failedLogoutKeepsSessionUntilServerRevocationCanSucceed() async throws {
  let auth=try client();defer{auth.clearLocalSession()}
  AuthURLProtocol.response=(200,accountData);await auth.restore()
  AuthURLProtocol.response=(503,Data())
  #expect(await auth.logout() == false)
  #expect(auth.account?.id == "account-one")
  #expect(auth.sessionToken == token)
 }
 @Test func obsoleteLogoutCannotClearCurrentSessionState() async throws {
  let auth=try client();defer{auth.clearLocalSession();AuthURLProtocol.delayed=false;AuthURLProtocol.pending=nil}
  AuthURLProtocol.response=(401,Data())
  AuthURLProtocol.delayed=true
  let task=Task {await auth.logout()}
  for _ in 0..<100 where AuthURLProtocol.pending == nil {try await Task.sleep(for:.milliseconds(10))}
  #expect(AuthURLProtocol.pending != nil)
  auth.clearLocalSession()
  AuthURLProtocol.pending?()
  #expect(await task.value == false)
 }
 @Test func onboardingStopsWhenConnectedProviderStatusCannotBeRead() async throws {
  try SessionKeychain.write(token,address:"google-login:"+address)
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[AuthURLProtocol.self]
  let defaults=UserDefaults(suiteName:"sumora.auth.unit-tests")!
  defer {defaults.removePersistentDomain(forName:"sumora.auth.unit-tests")}
  let dependencies=AppDependencies(address:address,session:URLSession(configuration:config),defaults:defaults)
  defer{dependencies.auth.clearLocalSession()}
  AuthURLProtocol.handler={request in
   if request.url?.path == "/v1/gmail/connection" {return (503,Data(#"{"error":{"code":"GMAIL_UNAVAILABLE","message":"Gmail status unavailable"}}"#.utf8))}
   if request.url?.path == "/v1/indmoney/connection" {return (200,Data(#"{"connected":false,"status":"disconnected"}"#.utf8))}
   if request.url?.path == "/v1/zerodha/portfolio" {return (200,try! Data(contentsOf:Bundle.main.url(forResource:"empty",withExtension:"json")!))}
   return (200,Data(#"{"account":{"id":"account-one","email":"owner@example.com","onboardingCompleted":false}}"#.utf8))
  }
  defer{AuthURLProtocol.handler=nil}
  await dependencies.auth.restore()
  await dependencies.fetchConsolidatedHoldings()
  #expect(dependencies.setupError == "Gmail status unavailable")
  #expect(dependencies.auth.account?.onboardingCompleted == false)
 }
 @Test func GoogleCallbackRejectsStateMismatchAndDuplicateClaims() throws {
  let code=String(repeating:"b",count:64)
  #expect(try GoogleLoginCallback.code(from:URL(string:"sumora://login?state=expected&code="+code)!,expectedState:"expected") == code)
  for suffix in ["state=wrong&code="+code,"state=expected&code="+code+"&code="+code,"state=expected&error=LOGIN_FAILED"] {
   #expect(throws:(any Error).self){try GoogleLoginCallback.code(from:URL(string:"sumora://login?"+suffix)!,expectedState:"expected")}
  }
 }
}
private final class AuthURLProtocol:URLProtocol,@unchecked Sendable {
 nonisolated(unsafe) static var response:(Int,Data)=(200,Data())
 nonisolated(unsafe) static var request:URLRequest?
 nonisolated(unsafe) static var delayed=false
 nonisolated(unsafe) static var pending:(()->Void)?
 nonisolated(unsafe) static var handler:((URLRequest)->(Int,Data))?
 override class func canInit(with request:URLRequest)->Bool {true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading(){
  Self.request=request
  let result=Self.handler?(request) ?? Self.response
  let deliver={ [self] in
   let response=HTTPURLResponse(url:request.url!,statusCode:result.0,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
   client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
   client?.urlProtocol(self,didLoad:result.1);client?.urlProtocolDidFinishLoading(self)
  }
  if Self.delayed {Self.pending=deliver}else{deliver()}

 }
 override func stopLoading(){}
}
