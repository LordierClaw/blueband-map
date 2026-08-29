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
                            beginSelection(candidate)
                        } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                        .disabled(candidateActionsDisabled)
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
                            .disabled(isSelecting || model.sessionState != .idle)
                        Spacer()
                        Button("Dừng") { Task { await model.stopScan() } }
                            .disabled(isSelecting || model.sessionState != .scanning)
                    }
                    Button("Đóng") {
                        Task {
                            if model.sessionState == .scanning { await model.stopScan() }
                            dismiss()
                        }
                    }
                    .disabled(isSelecting)
                }

                if let error = model.errorMessage {
                    Section("Lỗi an toàn") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Chọn band")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.sessionState == .scanning || isSelecting)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(candidate))
        .accessibilityHint("Chạm hai lần để kết nối")
    }

    private func beginSelection(_ candidate: BandCandidate) {
        guard !isSelecting else { return }
        isSelecting = true
        Task { await select(candidate) }
    }

    private func select(_ candidate: BandCandidate) async {
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

    private var candidateActionsDisabled: Bool {
        isSelecting || (model.sessionState != .idle && model.sessionState != .scanning)
    }

    private func accessibilityLabel(_ candidate: BandCandidate) -> String {
        let rememberedStatus = model.rememberedBand?.id == candidate.id ? "Đã nhớ" : "Chưa nhớ"
        let signalStatus = candidate.rssi.map { "RSSI \($0) dBm" } ?? "Đã biết bởi iOS"
        return "\(candidate.name), \(rememberedStatus), \(signalStatus), UUID \(shortenedUUID(candidate.id))"
    }
}
