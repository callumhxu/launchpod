import Foundation

/// Reads Core Animation filter objects (`CAFilter`) set on layers, through key-value coding.
nonisolated enum CoreAnimationFilterReading {
    /// The filter-type name a filter was created with, such as `gaussianBlur`.
    static func type(of filter: Any) -> String? {
        (filter as? NSObject)?.value(forKey: "type") as? String
    }

    /// The filter types in `filters`, in order.
    static func types(_ filters: [Any]?) -> [String] {
        (filters ?? []).compactMap { type(of: $0) }
    }

    /// The first filter of `type` in `filters`.
    static func first(_ type: String, in filters: [Any]?) -> NSObject? {
        (filters ?? []).first { self.type(of: $0) == type } as? NSObject
    }

    static func number(_ key: String, of filter: NSObject?) -> Double? {
        (filter?.value(forKey: key) as? NSNumber)?.doubleValue
    }

    /// The 20 row-major values of a `colorMatrix` filter's `inputColorMatrix`.
    static func colorMatrix(of filter: NSObject?) -> [Float]? {
        guard let value = filter?.value(forKey: "inputColorMatrix") as? NSValue else { return nil }
        var matrix = [Float](repeating: .nan, count: 20)
        matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: $0.count) }
        return matrix
    }
}
