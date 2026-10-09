import Foundation
import Testing
@testable import Sumora
struct INDmoneyConnectionTests {
 @Test func callbackRequiresExpectedStateAndExactlyOneCode() throws {
  let code=String(repeating:"a",count:64)
  #expect(try INDmoneyCallback.code(from:URL(string:"sumora://indmoney?state=expected&code=\(code)")!,expectedState:"expected")==code)
  for value in ["sumora://zerodha?state=expected&code=\(code)","sumora://indmoney?state=wrong&code=\(code)","sumora://indmoney?state=expected&code=short","sumora://indmoney?state=expected&code=\(code)&code=\(code)","sumora://indmoney?state=expected&state=wrong&code=\(code)"] {
   #expect(throws:(any Error).self){try INDmoneyCallback.code(from:URL(string:value)!,expectedState:"expected")}
  }
 }
}
