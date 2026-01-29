import Foundation
import CoreGraphics

func movingAverage(values: [CGFloat], window: Int) -> [CGFloat] {
    guard window > 1, values.count > 1 else { return values }
    let half = window / 2
    var result: [CGFloat] = Array(repeating: 0, count: values.count)
    for i in 0..<values.count {
        let start = max(0, i - half)
        let end = min(values.count - 1, i + half)
        let count = end - start + 1
        let sum = values[start...end].reduce(CGFloat(0), +)
        result[i] = sum / CGFloat(count)
    }
    return result
}

func standardDeviation(values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
    return sqrt(variance)
}
