import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ErrorLogView: View {
    @ObservedObject private var errorLog = ErrorLogService.shared
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            Section{
                Picker("最多保留", selection: Binding(
                    get: { errorLog.maximumEntryCount },
                    set: { errorLog.setMaximumEntryCount($0) }
                )) {
                    Text("10 条").tag(10)
                    Text("20 条").tag(20)
                    Text("50 条").tag(50)
                    Text("不限").tag(0)
                }
            }

            if errorLog.entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "暂无错误记录",
                        systemImage: "checkmark.circle",
                        description: Text("当记录到错误时将会显示在这里。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section("错误日志") {
                    ForEach(errorLog.entries) { entry in
                        NavigationLink {
                            ErrorLogDetailView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.context).font(.headline)
                                Text(entry.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("错误记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) { showingClearConfirmation = true }
                    .disabled(errorLog.entries.isEmpty)
            }
        }
        .confirmationDialog("清空所有错误记录？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空", role: .destructive) { errorLog.clear() }
        }
    }
}

private struct ErrorLogDetailView: View {
    let entry: ErrorLogEntry

    private var fullText: String {
        [
            "时间：\(entry.timestamp.formatted(date: .long, time: .standard))",
            "位置：\(entry.context)",
            entry.domain.map { "错误域：\($0)" },
            entry.code.map { "错误码：\($0)" },
            "来源：\(entry.source)",
            "\n错误信息：\n\(entry.details ?? entry.message)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            Text(fullText)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("错误详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
#if canImport(UIKit)
            ToolbarItem(placement: .topBarTrailing) {
                Button("复制") { UIPasteboard.general.string = fullText }
            }
#endif
        }
    }
}
