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

    init(title: String = "导入登入数据", onImported: @escaping () -> Void) {
        self.title = title
        self.onImported = onImported
    }

    var body: some View {
        Button(title) {
            showImporter = true
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try LoginImportService.importFrom(url: url)
                    onImported()
                } catch {
                    print(error)
                }

            case .failure(let error):
                print(error)
            }
        }
    }
}
