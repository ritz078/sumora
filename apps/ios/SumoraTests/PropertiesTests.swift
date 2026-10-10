import Foundation
import Testing
@testable import Sumora

@Suite(.serialized) @MainActor
struct PropertiesTests {
 private let property = """
 {"id":"11111111-1111-4111-8111-111111111111","name":"Apartment","estimatedValue":"10000000","ownershipPercent":"50","valuationDate":"2026-10-01","purchaseCost":"8000000","updatedAt":1790812800000}
 """
 @Test func legacyPropertyDecodesAtFullValueAndFiltersAsRealEstate() throws {
  let p=try JSONDecoder().decode(PropertyEntry.self,from:Data(property.utf8))
  #expect(p.estimatedValue.value == Decimal(10000000))
  let raw="""
  {"id":"property:test","name":"Apartment","symbol":"PROPERTY","assetClass":"realEstate","accountID":"properties","quantity":"1","unit":"property","invested":"0","costBasisKnown":false,"value":"10000000","gain":null,"gainPercent":null,"quote":null,"quoteCurrency":"INR","fxRate":"1","fxAt":null,"quoteAt":"2026-10-01T00:00:00Z","source":"Manually entered","priceBasis":"Full property value","history":[],"propertyTerms":\(property)}
  """
  let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
  let holding=try decoder.decode(Holding.self,from:Data(raw.utf8))
  #expect(holding.propertyTerms?.estimatedValue.value == holding.value?.value)
  #expect(HoldingsQuery(assetClass:.realEstate).apply(to:[holding]).count == 1)
  #expect(holding.gain == nil && holding.dailyGain == nil)
 }
 @Test func fullPropertyCostAndGainIgnoreLegacyShareAndMissingCostStaysUnknown() throws {
  let property=try JSONDecoder().decode(PropertyEntry.self,from:Data(property.utf8))
  let metrics=PropertyValuation(properties:[property])
  #expect(metrics.value.value == 10000000)
  #expect(metrics.cost.value == 8000000)
  #expect(metrics.gain?.value == 2000000)
  #expect(metrics.percent?.value == 25)
  let unknown=PropertyEntry(id:"unknown",name:"Land",estimatedValue:DecimalValue(500000),valuationDate:"2026-10-01",purchaseCost:nil,updatedAt:0)
  #expect(PropertyValuation(properties:[property,unknown]).gain == nil)
  #expect(PropertyInput.amount("95,00,000") == 9500000)
  #expect(PropertyInput.amount("100oops") == nil)
  #expect(PropertyInput.amount("-1") == nil)
 }
 @Test func failedPropertyEditsRetainDataAndSuccessfulSaveAndRemoveUpdateTheList() async {
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[PropertyProtocol.self]
  let session=URLSession(configuration:config);defer { session.invalidateAndCancel() }
  let connection=PropertiesConnection(session:session)
  connection.configure(address:"https://example.com",token:String(repeating:"1",count:64))
  PropertyProtocol.responses=[(200,"{\"properties\":[\(property)]}"),(400,"{\"error\":{\"code\":\"INVALID_PROPERTY\",\"message\":\"Invalid amount\"}}"),(200,"{\"property\":\(property.replacingOccurrences(of:"Apartment",with:"Updated"))}"),(200,"{\"removed\":true}")]
  await connection.refresh();#expect(connection.properties.count == 1)
  #expect(PropertyProtocol.paths.last == "/v1/properties")
  let failed=await connection.save(id:connection.properties[0].id,name:"Bad",value:"invalid",date:"2026-10-01",cost:"")
  #expect(!failed && connection.properties[0].name == "Apartment" && connection.errorMessage != nil)
  let saved=await connection.save(id:connection.properties[0].id,name:"Updated",value:"10000000",date:"2026-10-01",cost:"")
  #expect(saved && connection.properties.count == 1 && connection.properties[0].name == "Updated")
  let removed=await connection.remove(id:connection.properties[0].id);#expect(removed && connection.properties.isEmpty)
  connection.configure(address:"https://example.com",token:nil);#expect(connection.properties.isEmpty)
 }
}
private final class PropertyProtocol:URLProtocol,@unchecked Sendable {
 nonisolated(unsafe) static var paths:[String]=[]
 nonisolated(unsafe) static var responses:[(Int,String)]=[]
 override class func canInit(with request:URLRequest)->Bool { true }
 override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
 override func startLoading() {
  Self.paths.append(request.url!.path)
  let response=Self.responses.removeFirst()
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:response.0,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Data(response.1.utf8));client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
