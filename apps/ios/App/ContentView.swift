import SwiftUI
import BlueBandCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isConfigPresented = false
    @State private var isBandPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                devicesSection
                connectionSection
                proofSection
                rpkSection
                m1Section
                echoSection
                if let error = model.errorMessage {
                    Section("Lỗi an toàn") { Text(error).foregroundStyle(.red) }
                }
                Section("Build") {
                    LabeledContent("iOS", value: BlueBandProduct.version)
                    LabeledContent("Envelope", value: "v\(ApplicationEnvelope.version)")
                    Text("Foreground-only • Xiaomi Smart Band 10")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(BlueBandProduct.displayName)
            .toolbar {
                Button("Cấu hình") { isConfigPresented = true }
            }
            .sheet(isPresented: $isConfigPresented) {
                ConfigView(model: model)
            }
            .sheet(isPresented: $isBandPickerPresented) {
                BandPickerView(model: model)
            }
        }
    }

    private var devicesSection: some View {
        Section("Xiaomi Smart Band 10") {
            Button("Kết nối") { isBandPickerPresented = true }
                .disabled(model.sessionState != .idle)
            Text("Chỉ chọn Band 10. Mi Fitness phải đóng trong lúc BlueBandMap giữ phiên Xiaomi.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectionSection: some View {
        Section("Phiên") {
            LabeledContent("Trạng thái", value: model.sessionState.rawValue)
            if model.sessionState != .idle && model.sessionState != .scanning {
                Button("Ngắt kết nối", role: .destructive) { Task { await model.disconnect() } }
            }
        }
    }

    private var proofSection: some View {
        Section("Device proof") {
            LabeledContent("Battery", value: model.snapshot.batteryLevel.map { "\($0)%" } ?? "—")
            LabeledContent("Model", value: model.snapshot.model ?? "—")
            LabeledContent("Firmware", value: model.snapshot.firmware ?? "—")
        }
    }

    private var rpkSection: some View {
        Section("RPK trust") {
            LabeledContent("Package", value: BlueBandProduct.rpkPackage)
            LabeledContent("Handshake", value: rpkLabel)
            Button("Reset trusted fingerprint", role: .destructive) { Task { await model.resetTrustedRPK() } }
            Text("TOFU kiểm tra tính liên tục fingerprint, không xác minh certificate chain.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var echoSection: some View {
        Section("system.echo") {
            TextField("Payload", text: $model.echoInput)
            Button("Gửi echo") { Task { await model.sendEcho() } }.disabled(model.rpkState != .ready)
            ForEach(model.events) { item in
                HStack { Text(item.source.rawValue.uppercased()).font(.caption.bold()); Text(item.text); Spacer(); Text(item.delivery.rawValue).font(.caption2) }
            }
            if !model.events.isEmpty { Button("Xóa events") { model.clearEvents() } }
        }
    }

    private var m1Section: some View {
        Section("M1 · One Vietmap street PNG") {
            LabeledContent("Trạng thái", value: m1Label)
            Text("Tối đa 1 Static Map request mỗi lần bấm")
                .font(.caption).foregroundStyle(.secondary)
            if model.m1RequiresReconnect {
                Text("Cần ngắt kết nối và kết nối lại Band trước khi thử lại.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button("Tải và gửi M1") { Task { await model.startM1() } }
                .disabled(model.rpkState != .ready || m1IsBusy || model.m1RequiresReconnect)
        }
    }

    private var m1IsBusy: Bool {
        switch model.m1State {
        case .fetching, .transferring, .waitingForBand: return true
        case .idle, .displayed, .failed: return false
        }
    }

    private var m1Label: String {
        switch model.m1State {
        case .idle: return "Sẵn sàng"
        case .fetching: return "Đang tải PNG"
        case let .transferring(completed, total): return "Đang gửi \(completed)/\(total) ACK"
        case let .waitingForBand(_, hashPrefix): return "Chờ Band hiển thị · \(hashPrefix)"
        case let .displayed(_, hashPrefix): return "Đã hiển thị · \(hashPrefix)"
        case let .failed(code): return code
        }
    }

    private var rpkLabel: String {
        switch model.rpkState {
        case .locked: return "Chưa có phiên"
        case .waiting: return "Chờ mở app trên band"
        case .ready: return "Đã xác thực"
        case let .failed(message): return message
        }
    }
}
