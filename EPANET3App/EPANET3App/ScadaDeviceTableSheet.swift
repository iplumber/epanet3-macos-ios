import SwiftUI

/// SCADA 压力/流量设备表主体（用于独立 NSWindow；窗口标题栏显示表名）。
struct ScadaDeviceTablePanel: View {
    let kind: ScadaDeviceKind
    let devices: [ScadaDeviceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(kind == .pressure ? "压力测点" : "流量测点")
                    .font(.subheadline.weight(.semibold))
                Text("\(devices.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if devices.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(macOS)
                Table(devices) {
                    TableColumn("设备 ID", value: \.id)
                        .width(min: 60, ideal: 90)
                    TableColumn("名称", value: \.name)
                        .width(min: 60, ideal: 100)
                    TableColumn("模型 ID", value: \.model)
                        .width(min: 60, ideal: 80)
                    TableColumn("X") { dev in
                        Text(dev.x.map { String(format: "%.2f", $0) } ?? "-")
                    }
                    .width(min: 60, ideal: 90)
                    TableColumn("Y") { dev in
                        Text(dev.y.map { String(format: "%.2f", $0) } ?? "-")
                    }
                    .width(min: 60, ideal: 90)
                    TableColumn("口径", value: \.diameter)
                        .width(min: 40, ideal: 60)
                    TableColumn("标高", value: \.elevation)
                        .width(min: 40, ideal: 60)
                }
                #else
                List(devices) { dev in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(dev.id).font(.caption.bold())
                            Spacer()
                            Text(dev.model).font(.caption).foregroundColor(.secondary)
                        }
                        HStack {
                            Text(dev.name).font(.caption2)
                            Spacer()
                            if let x = dev.x, let y = dev.y {
                                Text("(\(String(format: "%.1f", x)), \(String(format: "%.1f", y)))")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                #endif
            }
        }
        .frame(minWidth: 560, minHeight: 340)
    }
}
