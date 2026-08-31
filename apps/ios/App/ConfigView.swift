import Foundation
import SwiftUI

struct ConfigView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                authKeySection
                tileMapKeySection
                serviceKeySection
                destinationSection
                rememberedBandSection
                if let error = model.errorMessage {
                    Section("Lỗi an toàn") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Cấu hình")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var authKeySection: some View {
        Section("AuthKey") {
            SecureField("32 ký tự hex", text: $model.authKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Lưu") { model.saveKey() }
                    .disabled(model.authKeyInput.isEmpty)
                Spacer()
                Button("Xóa", role: .destructive) { model.deleteKey() }
                    .disabled(!model.hasSavedKey)
            }
            if model.hasSavedKey { savedLabel }
        }
    }

    private var tileMapKeySection: some View {
        Section("Vietmap TileMap key") {
            SecureField("Nhập TileMap key", text: $model.tileMapKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Lưu") { model.saveVietmapKey(.tileMap) }
                    .disabled(model.tileMapKeyInput.isEmpty)
                Spacer()
                Button("Xóa", role: .destructive) { model.deleteVietmapKey(.tileMap) }
                    .disabled(!model.hasTileMapKey)
            }
            if model.hasTileMapKey { savedLabel }
        }
    }

    private var serviceKeySection: some View {
        Section("Vietmap Service/API key") {
            SecureField("Nhập Service/API key", text: $model.serviceKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Lưu") { model.saveVietmapKey(.service) }
                    .disabled(model.serviceKeyInput.isEmpty)
                Spacer()
                Button("Xóa", role: .destructive) { model.deleteVietmapKey(.service) }
                    .disabled(!model.hasServiceKey)
            }
            if model.hasServiceKey { savedLabel }
        }
    }

    private var rememberedBandSection: some View {
        Section("Band đã nhớ") {
            if let band = model.rememberedBand {
                LabeledContent("Tên", value: band.name)
                LabeledContent("UUID", value: shortenedUUID(band.id))
                LabeledContent(
                    "Kết nối gần nhất",
                    value: band.lastConnectedAt.formatted(date: .abbreviated, time: .shortened)
                )
                Button("Quên band", role: .destructive) { model.forgetBand() }
            } else {
                Text("Chưa có band đã nhớ").foregroundStyle(.secondary)
            }
            Button("Đóng") { dismiss() }
        }
    }

    private var destinationSection: some View {
        Section("Điểm đến") {
            TextField("Latitude", text: $model.destinationLatitudeInput)
                .keyboardType(.numbersAndPunctuation)
            TextField("Longitude", text: $model.destinationLongitudeInput)
                .keyboardType(.numbersAndPunctuation)
            Button("Lưu điểm đến") { model.saveDestination() }
            Text("Nhập tọa độ thật; bản này chưa có tìm kiếm địa điểm.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var savedLabel: some View {
        Label("Đã lưu trong Keychain", systemImage: "checkmark.shield")
            .foregroundStyle(.green)
    }

    private func shortenedUUID(_ id: UUID) -> String {
        let value = id.uuidString
        return "\(value.prefix(4))…\(value.suffix(4))"
    }
}
