import CoreGraphics

// Readable JSON shapes for CoreGraphics values in layouts.json.
// Foundation encodes CGRect as nested arrays ([[x, y], [w, h]]); these keep the file hand-editable.

/// `{"width": 1920, "height": 515}`
struct CodableSize: Codable, Hashable {
    var width: Double
    var height: Double

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }

    var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// `{"x": 100, "y": 0, "width": 308, "height": 120}`, display-local points, origin bottom-left.
struct CodableRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        let r = rect.standardized
        x = Double(r.origin.x)
        y = Double(r.origin.y)
        width = Double(r.size.width)
        height = Double(r.size.height)
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
