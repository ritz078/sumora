import Foundation
import Testing
@testable import Sumora

@Suite(.serialized)
struct GmailDocumentSyncTests {
 @MainActor @Test func oneSyncDrainsEachSourceAndContinuesAfterASourceFailure() async throws {
  DocumentURLProtocol.counts = [:]
  let configuration=URLSessionConfiguration.ephemeral
  configuration.protocolClasses=[DocumentURLProtocol.self]
  let gmail=GmailConnection(session:URLSession(configuration:configuration))
  gmail.configure(address:"https://example.com",token:String(repeating:"a",count:64))
  await gmail.syncDocuments()
  #expect(gmail.isBusy == false)
  #expect(gmail.syncResults.map(\.source.rawValue) == ["gold","hdfc","nps","bonds"])
  #expect(gmail.syncResults.map(\.imported) == [2,0,1,1])
  #expect(gmail.syncResults[1].error != nil)
  #expect(gmail.syncResults[2].error == nil)
  #expect(gmail.errorMessage?.contains("HDFC") == true)
 }
}
private final class DocumentURLProtocol:URLProtocol,@unchecked Sendable {
 nonisolated(unsafe) static var counts:[String:Int]=[:]
 override class func canInit(with request:URLRequest)->Bool { true }
 override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
 override func startLoading() {
  let body=request.httpBody ?? request.httpBodyStream.map { stream in
   stream.open();defer{stream.close()};var data=Data();var buffer=[UInt8](repeating:0,count:1024)
   while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(contentsOf:buffer.prefix(n))};return data
  } ?? Data()
  let input=(try? JSONSerialization.jsonObject(with:body)) as? [String:String]
  let source=input?["source"]
  var object:[String:Any]=["sources":["gold","hdfc","nps","bonds"]]
  if let source {
   let n=(Self.counts[source] ?? 0)+1;Self.counts[source]=n
   let pending=source=="gold" ? n<=2 : (source=="nps" || source=="bonds") ? n<=1 : false
   object=["source":source,"imported":pending ? 1:0,"status":source=="hdfc" ? "failed":pending ? "imported":"up_to_date","pending":pending,"error":source=="hdfc" ? "HDFC statement needs review.":NSNull()]
  }
  let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:object))
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
