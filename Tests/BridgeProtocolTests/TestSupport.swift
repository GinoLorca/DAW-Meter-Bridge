import Foundation
import Testing

/// UTF-8 bytes of a JSON literal.
func datagram(_ json: String) -> Data { Data(json.utf8) }

/// Parses encoded output generically, to check exact keys and explicit nulls.
func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The protocol's 101-sample volume curve example with the elided samples filled in:
/// `x = k/100`, `db` null at 0, -70 at 0.01 and +6 at 1.0.
func helloCurveJSON() -> String {
    let xs = (0...100).map { (k: Int) -> String in
        switch k {
        case 0: "0.0"
        case 100: "1.0"
        default: String(Double(k) / 100)
        }
    }
    let dbs = (0...100).map { k -> String in
        switch k {
        case 0: "null"
        case 1: "-70.0"
        case 100: "6.0"
        default: String(format: "%.1f", -70.0 + 76.0 * Double(k - 1) / 99.0)
        }
    }
    return #"{"x":[\#(xs.joined(separator: ","))],"db":[\#(dbs.joined(separator: ","))]}"#
}
