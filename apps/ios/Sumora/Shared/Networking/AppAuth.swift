import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import UIKit

struct AppAccount:Decodable {
 let id:String
 let email:String
 let onboardingCompleted:Bool
}
enum GoogleLoginCallback {
 static func code(from url:URL,expectedState:String)throws->String {
  guard url.scheme == "sumora",url.host == "login",url.path.isEmpty,
        let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,
        items.filter({$0.name == "state"}).count == 1,
        items.first(where:{$0.name == "state"})?.value == expectedState,
        !items.contains(where:{$0.name == "error"}),
        items.filter({$0.name == "code"}).count == 1,
        let code=items.first(where:{$0.name == "code"})?.value,
        code.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else {
   throw ZerodhaError.message("Google sign-in could not be verified. Please try again.")
  }
  return code
 }
}

extension Notification.Name {
 static let appSessionInvalidated=Notification.Name("sumora.appSessionInvalidated")
}
func checkAppSession(_ response:HTTPURLResponse,data:Data,token:String?) {
 guard response.statusCode == 401,let token,
       (try? JSONDecoder().decode(APIErrorResponse.self,from:data).error.code) == "SIGN_IN_REQUIRED" else {return}
 NotificationCenter.default.post(name:.appSessionInvalidated,object:token)
}

@MainActor @Observable
final class AppAuth:NSObject,ASWebAuthenticationPresentationContextProviding {
 private(set) var sessionToken:String?
 private(set) var account:AppAccount?
 private(set) var isValidating=true
 private(set) var isBusy=false
 var errorMessage:String?
 private(set) var address:String
 @ObservationIgnored private let session:URLSession
 @ObservationIgnored private var authentication:ASWebAuthenticationSession?
 @ObservationIgnored private var generation=UUID()
 private var storageKey:String { "google-login:"+address }
 init(address:String,restoreSession:Bool=true,session:URLSession = .shared) {
  self.address=address;self.session=session
  sessionToken=restoreSession ? SessionKeychain.read("google-login:"+address):nil
  super.init()
 }
 func restore() async {
  guard !isBusy else {return}
  guard sessionToken != nil else {isValidating=false;return}
  isValidating=true;isBusy=true;let current=generation
  defer {if generation == current {isValidating=false;isBusy=false}}
  do {
   let result:AccountResponse=try await send("session",method:"GET",token:sessionToken)
   guard current == generation else {return}
   account=result.account;errorMessage=nil
  }catch AuthError.unauthorized {if current == generation {clearLocalSession()}}
  catch {if current == generation {errorMessage=error.localizedDescription}}
 }
 func signIn() async {
  guard !isBusy else {return}
  isBusy=true;errorMessage=nil;let current=generation
  defer {if current == generation {isBusy=false;authentication=nil;isValidating=false}}
  do {
   let verifier=UUID().uuidString.replacingOccurrences(of:"-",with:"")+UUID().uuidString.replacingOccurrences(of:"-",with:"")
   let challenge=SHA256.hash(data:Data(verifier.utf8)).map{String(format:"%02x",$0)}.joined()
   let start:Start
   if let legacy=SessionKeychain.read(address) {
    do {start=try await send("google/start",body:["challenge":challenge],token:legacy)}
    catch AuthError.unauthorized {start=try await send("google/start",body:["challenge":challenge])}
   } else {start=try await send("google/start",body:["challenge":challenge])}
   guard current == generation else {return}
   guard let url=URL(string:start.loginURL),url.scheme == "https",url.host == "accounts.google.com" else {throw PortfolioAPIError.invalidSnapshot}
   let callback:URL=try await withCheckedThrowingContinuation {continuation in
    let auth=ASWebAuthenticationSession(url:url,callbackURLScheme:"sumora") {url,error in
     if let url {continuation.resume(returning:url)}else{continuation.resume(throwing:error ?? ZerodhaError.message("Sign-in was cancelled."))}
    }
    auth.presentationContextProvider=self;authentication=auth
    if !auth.start(){continuation.resume(throwing:ZerodhaError.message("The sign-in window couldn't open."))}
   }
   guard current == generation else {return}
   let code=try GoogleLoginCallback.code(from:callback,expectedState:start.state)
   let result:Claim=try await send("google/claim",body:["code":code,"verifier":verifier])
   guard current == generation else {return}
   guard result.sessionToken.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else {throw PortfolioAPIError.invalidSnapshot}
   try SessionKeychain.write(result.sessionToken,address:storageKey)
   SessionKeychain.remove(address)
   sessionToken=result.sessionToken;account=result.account
  }catch {
   if current == generation && (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {errorMessage=error.localizedDescription}
  }
 }
 func completeOnboarding() async -> Bool {
  let current=generation
  do {
   let result:AccountResponse=try await send("onboarding",token:sessionToken)
   guard current == generation else {return false}
   account=result.account;errorMessage=nil;return true
  }catch {if current == generation {errorMessage=error.localizedDescription};return false}
 }
 func logout() async -> Bool {
  guard !isBusy else {return false}
  isBusy=true;let current=generation
  defer {if current == generation {isBusy=false}}
  do {
   let _:Logout=try await send("session",method:"DELETE",token:sessionToken)
   guard current == generation else {return false}
   clearLocalSession();return true
  }catch AuthError.unauthorized {
   guard current == generation else {return false}
   clearLocalSession();return true
  }
  catch {if current == generation {errorMessage="Couldn't sign out securely. Check your connection and try again."};return false}
 }
 func clearLocalSession() {
  generation=UUID();authentication?.cancel();authentication=nil
  SessionKeychain.remove(storageKey)
  sessionToken=nil;account=nil;isBusy=false;isValidating=false;errorMessage=nil
  URLCache.shared.removeAllCachedResponses()
 }
 func presentationAnchor(for session:ASWebAuthenticationSession)->ASPresentationAnchor {
  UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
 }
 private func send<T:Decodable>(_ path:String,method:String="POST",body:[String:String]?=nil,token:String?=nil) async throws ->T {
  guard let base=APIConfiguration.baseURL(address)else{throw HTTPPortfolioError.configuration}
  var request=URLRequest(url:base.appendingPathComponent("v1/auth/"+path))
  request.httpMethod=method;request.timeoutInterval=20;request.cachePolicy = .reloadIgnoringLocalCacheData
  request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  if let token {request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")}
  if let body {request.httpBody=try JSONEncoder().encode(body)}
  let (data,response)=try await session.data(for:request)
  guard let http=response as? HTTPURLResponse else{throw PortfolioAPIError.invalidSnapshot}
  if http.statusCode == 401 {throw AuthError.unauthorized}
  guard (200..<300).contains(http.statusCode)else{throw ZerodhaError.message((try? JSONDecoder().decode(APIErrorResponse.self,from:data).error.message) ?? "Sign-in request failed. Try again.")}
  return try JSONDecoder().decode(T.self,from:data)
 }
 private struct Start:Decodable {let state:String;let loginURL:String}
 private struct Claim:Decodable {let sessionToken:String;let account:AppAccount}
 private struct AccountResponse:Decodable {let account:AppAccount}
 private struct Logout:Decodable {let loggedOut:Bool}
 enum AuthError:LocalizedError {
  case unauthorized
  var errorDescription:String? {"Your app session expired. Sign in again."}
 }
}
