import Foundation
import CoreGraphics

struct RepSegment {
    let startIndex: Int
    let bottomIndex: Int
    let endIndex: Int
}

struct RepSegmenter {
    static func segment(series: PoseSeries, liftType: LiftType) -> [RepSegment] {
        guard series.frames.count > 3 else { return [] }
        let primaryJoint: Joint = (liftType == .bench) ? .wrist : .hip
        let values = series.frames.compactMap { $0.points[primaryJoint]?.y }
        if values.count != series.frames.count { return [] }

        let smooth = movingAverage(values: values, window: 5)
        let (maxima, minima) = localExtrema(values: smooth)
        let minFrames = max(6, Int(series.fps * 0.6))
        let filteredMax = filterByDistance(indices: maxima, values: smooth, minDistance: minFrames, preferHigher: true)
        let filteredMin = filterByDistance(indices: minima, values: smooth, minDistance: minFrames, preferHigher: false)

        guard filteredMax.count >= 2 else { return [] }

        var segments: [RepSegment] = []
        for idx in 0..<(filteredMax.count - 1) {
            let start = filteredMax[idx]
            let end = filteredMax[idx + 1]
            if end - start < minFrames { continue }
            if let bottom = filteredMin.filter({ $0 > start && $0 < end }).min(by: { smooth[$0] < smooth[$1] }) {
                segments.append(RepSegment(startIndex: start, bottomIndex: bottom, endIndex: end))
            }
        }
        return segments
    }

    private static func localExtrema(values: [CGFloat]) -> (maxima: [Int], minima: [Int]) {
        guard values.count >= 3 else { return ([], []) }
        var maxima: [Int] = []
        var minima: [Int] = []
        for i in 1..<(values.count - 1) {
            if values[i] > values[i - 1] && values[i] > values[i + 1] {
                maxima.append(i)
            }
            if values[i] < values[i - 1] && values[i] < values[i + 1] {
                minima.append(i)
            }
        }
        return (maxima, minima)
    }

    private static func filterByDistance(indices: [Int], values: [CGFloat], minDistance: Int, preferHigher: Bool) -> [Int] {
        var result: [Int] = []
        for idx in indices {
            guard let last = result.last else {
                result.append(idx)
                continue
            }
            if idx - last >= minDistance {
                result.append(idx)
            } else {
                let better = preferHigher ? (values[idx] > values[last]) : (values[idx] < values[last])
                if better {
                    result[result.count - 1] = idx
                }
            }
        }
        return result
    }
}
