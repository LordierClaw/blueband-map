import Foundation
import SwiftUI
import BlueBandCore

struct BandPickerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSelecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(model.pickerCandidates) { candidate in
                        Button {
                            Task { await select(candidate) }
                        } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSelecting)
                    }

                    if model.pickerCandidates.isEmpty {
                        Text(model.sessionState == .scanning ? "Đang quét…" : "Không tìm thấy band")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Xiaomi Smart Band 10")
                } footer: {
                    Text("Chỉ chọn Band 10. Mi Fitness phải đóng trong lúc BlueBandMap giữ phiên Xiaomi.")
                }

                Section {
                    HStack {
                        Button("Quét lại") { Task { await model.scan() } }
                            .disabled(model.sessionState != .idle)
                        Spacer()
                        Button("Dừng") { Task { await model.stopScan() } }
                            .disabled(model.sessionState != .scanning)
                    }
                    Button("Đóng") {
                        Task {
                            if model.sessionState == .scanning { await model.stopScan() }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Chọn band")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.sessionState == .scanning)
            .task {
                if model.sessionState == .idle { await model.scan() }
            }
        }
    }

    private func candidateRow(_ candidate: BandCandidate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.rememberedBand?.id == candidate.id ? "star.fill" : "circle")
                .foregroundStyle(
                    model.rememberedBand?.id == candidate.id ? Color.yellow : Color.secondary
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name).foregroundStyle(.primary)
                Text(candidate.rssi.map { "RSSI \($0) dBm" } ?? "Đã biết bởi iOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortenedUUID(candidate.id))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func select(_ candidate: BandCandidate) async {
        guard !isSelecting else { return }
        isSelecting = true
        defer { isSelecting = false }
        await model.connect(to: candidate)
        if model.sessionState != .idle && model.sessionState != .scanning {
            dismiss()
        }
    }

    private func shortenedUUID(_ id: UUID) -> String {
        let value = id.uuidString
        return "\(value.prefix(4))…\(value.suffix(4))"
    }
}
