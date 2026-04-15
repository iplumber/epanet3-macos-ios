import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// 「导入 SCADA」弹窗：压力 / 流量两个标签页，各自选 CSV 后预览表头行数。
struct ScadaImportSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case pressure = "压力设备表"
        case flow = "流量设备表"
    }

    @State private var tab: Tab = .pressure
    @State private var pressureURL: URL?
    @State private var pressurePreview: String = ""
    @State private var pressureCount: Int?
    @State private var flowURL: URL?
    @State private var flowPreview: String = ""
    @State private var flowCount: Int?
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("导入 SCADA 设备表")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Group {
                switch tab {
                case .pressure:
                    csvTabContent(
                        label: "压力设备 CSV（MODEL 列为节点 ID）",
                        url: $pressureURL,
                        preview: $pressurePreview,
                        count: $pressureCount,
                        kind: .pressure
                    )
                case .flow:
                    csvTabContent(
                        label: "流量设备 CSV（MODEL 列为管段 ID）",
                        url: $flowURL,
                        preview: $flowPreview,
                        count: $flowCount,
                        kind: .flow
                    )
                }
            }
            .padding(16)

            if let err = importError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入") {
                    appState.commitScadaImport(pressureCSVURL: pressureURL, flowCSVURL: flowURL)
                    if appState.errorMessage == nil {
                        dismiss()
                    } else {
                        importError = appState.errorMessage
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pressureURL == nil && flowURL == nil)
            }
            .padding(16)
        }
        .frame(width: 480, height: 400)
    }

    @ViewBuilder
    private func csvTabContent(
        label: String,
        url: Binding<URL?>,
        preview: Binding<String>,
        count: Binding<Int?>,
        kind: ScadaDeviceKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text(url.wrappedValue?.lastPathComponent ?? "未选择")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(url.wrappedValue == nil ? .secondary : .primary)

                Button("选择文件…") {
                    chooseCSV(url: url, preview: preview, count: count, kind: kind)
                }
            }

            if let c = count.wrappedValue {
                Text("已解析 \(c) 条设备记录")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if !preview.wrappedValue.isEmpty {
                Text("表头预览")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(preview.wrappedValue)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(4)
            }

            Spacer()
        }
    }

    private func chooseCSV(
        url: Binding<URL?>,
        preview: Binding<String>,
        count: Binding<Int?>,
        kind: ScadaDeviceKind
    ) {
        let panel = NSOpenPanel()
        panel.title = kind == .pressure ? "选择压力设备 CSV" : "选择流量设备 CSV"
        panel.allowedContentTypes = []
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        url.wrappedValue = chosen
        importError = nil
        do {
            let rows = try ScadaCSVImporter.loadDeviceRows(url: chosen, kind: kind)
            count.wrappedValue = rows.count
            let header = try String(contentsOf: chosen, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .prefix(4)
                .joined(separator: "\n")
            preview.wrappedValue = header
        } catch {
            preview.wrappedValue = ""
            count.wrappedValue = nil
            importError = error.localizedDescription
        }
    }
}
#endif
