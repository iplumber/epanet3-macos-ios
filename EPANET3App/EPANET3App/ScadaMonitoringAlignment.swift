import Foundation

/// 将外部监测序列按**仿真时间轴（秒）**做零阶保持（ZOH）：每个目标时刻取「时间不晚于该时刻的最近一条」外部样本（0:00 对 0:00；5min 数据在 0:01…0:04 仍保持 0:00 的值，0:05 起用 0:05 的值）。
enum ScadaMonitoringAlignment {
    /// `samples`: `(秒自当日 0:00 起, 原始值)`，已按时间升序、同一设备。
    static func zohResampleToSimulationSeconds(targetSeconds: [Int], samples: [(Int, Double)]) -> [Float] {
        let sorted = samples.sorted { $0.0 < $1.0 }
        guard !sorted.isEmpty else { return targetSeconds.map { _ in .nan } }
        var out: [Float] = []
        out.reserveCapacity(targetSeconds.count)
        var idx = 0
        for t in targetSeconds {
            while idx + 1 < sorted.count && sorted[idx + 1].0 <= t {
                idx += 1
            }
            let v: Float
            if sorted[idx].0 <= t {
                v = Float(sorted[idx].1)
            } else {
                // 目标时刻早于第一条外部样本：无「不晚于 t」的样本，保持 NaN（勿误用首条样本填 0:01…）
                v = .nan
            }
            out.append(v)
        }
        return out
    }

    /// 将每条时序行的绝对时间转为「从参考日 0:00 起的秒数」（与 EPANET 从 0 开始的仿真秒一致）。
    static func secondsSinceMidnight(of dates: [Date], calendar: Calendar = .current) -> [Int] {
        guard let first = dates.min() else { return [] }
        let start = calendar.startOfDay(for: first)
        return dates.map { d in
            Int(d.timeIntervalSince(start).rounded())
        }
    }

    /// 与 `AppState.discreteSimulationTimePoints` / 工具栏时间轴一致。
    static func discreteSimulationTimePoints(durationSeconds: Int, hydraulicStepSeconds: Int) -> [Int] {
        guard durationSeconds > 0 else { return [0] }
        let s = max(1, hydraulicStepSeconds)
        var pts: [Int] = []
        var t = 0
        while true {
            pts.append(t)
            if t >= durationSeconds { break }
            let next = t + s
            if next >= durationSeconds {
                if pts.last != durationSeconds { pts.append(durationSeconds) }
                break
            }
            t = next
        }
        return pts
    }

    /// 将已导入的监测序列（与 `sourceTimes` 等长）按**时刻**零阶保持到 `targetTimes`（通常为本次 `timeSeriesResults.timePoints`）。  
    /// 与导入时步长或点数是否一致无关，不按下标顺序硬套。
    static func zohAlignSeriesToTargetTimes(values: [Float], sourceTimes: [Int], targetTimes: [Int]) -> [Float]? {
        guard !targetTimes.isEmpty else { return nil }
        let n = min(values.count, sourceTimes.count)
        guard n > 0 else { return nil }
        var samples: [(Int, Double)] = []
        samples.reserveCapacity(n)
        for i in 0..<n {
            samples.append((sourceTimes[i], Double(values[i])))
        }
        let deduped = dedupeSameSecondSorted(samples)
        return zohResampleToSimulationSeconds(targetSeconds: targetTimes, samples: deduped)
    }

    /// 同一时间戳多条记录时保留最后一条。
    static func dedupeSameSecondSorted(_ samples: [(Int, Double)]) -> [(Int, Double)] {
        let s = samples.sorted { $0.0 < $1.0 }
        var out: [(Int, Double)] = []
        out.reserveCapacity(s.count)
        for x in s {
            if let last = out.last, last.0 == x.0 {
                out[out.count - 1] = x
            } else {
                out.append(x)
            }
        }
        return out
    }
}
