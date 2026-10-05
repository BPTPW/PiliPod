//
//  LoginImportView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct LoginImportView: View {
    let title: String
    let onImported: () -> Void

    @State private var showImporter = false
    @State private var importError: String?
    @State private var imported = false

    init(title: String = "导入账号", onImported: @escaping () -> Void) {
        self.title = title
        self.onImported = onImported
    }

    var body: some View {
        Button(title, systemImage: "square.and.arrow.down") {
            showImporter = true
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("确定") { importError = nil }
        } message: { Text(importError ?? "") }
        .alert("账号已导入", isPresented: $imported) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("已保留文件中的功能分工。未指定用途的账号可在“账号与隐私”中选择。")
        }
        .fileImporter(
            isPresented: $showImporter,
            // File providers may identify JSON exports as generic data or text.
            // Validate the actual JSON and account schema after selection.
            allowedContentTypes: [.data]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try LoginImportService.importFrom(url: url)
                    imported = true
                    onImported()
                } catch {
                    importError = error.localizedDescription
                }

            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }
}
