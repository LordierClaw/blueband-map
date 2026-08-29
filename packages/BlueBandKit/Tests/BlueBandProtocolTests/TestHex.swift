import Foundation
@testable import BlueBandProtocol

extension Data {
    init(testHex: String) {
        let compact = testHex.filter { !$0.isWhitespace }
        precondition(compact.count.isMultiple(of: 2))
        var output = Data(capacity: compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            output.append(UInt8(compact[index..<next], radix: 16)!)
            index = next
        }
        self = output
    }
}
