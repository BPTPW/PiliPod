//
//  DividerWithText.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct DividerWithText: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.secondary.opacity(0.3))
                .frame(height: 1)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

#Preview {
    DividerWithText(title: "刚刚更新")
}
