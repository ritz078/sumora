import Foundation
import Testing
@testable import Sumora
struct GmailConnectionTests {
 @Test func callbackRequiresExpectedStateAndExactlyOneCode() throws {
  let code=String(repeating:"a",count:64)
  #expect(try GmailCallback.code(from:URL(string:"sumora://gmail?state=expected&code=\(code)")!,expectedState:"expected")==code)
  for value in ["sumora://zerodha?state=expected&code=\(code)","sumora://gmail?state=wrong&code=\(code)","sumora://gmail?state=expected&code=short","sumora://gmail?state=expected&code=\(code)&code=\(code)","sumora://gmail?state=expected&state=wrong&code=\(code)"] {
   #expect(throws:(any Error).self){try GmailCallback.code(from:URL(string:value)!,expectedState:"expected")}
  }
 }
}
