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
                h1Section
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

    private var h1Section: some View {
        Section("H1 · Hybrid renderer POC") {
            LabeledContent("Trạng thái", value: h1Label)
            Text("Mỗi nút chạy một mode độc lập. Vector chỉ gửi scene tối đa 40 line primitives; không tự fallback sang raster.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(H1TestMode.allCases, id: \.self) { mode in
                Button(h1ModeLabel(mode)) {
                    Task { await model.startH1(mode: mode) }
                }
                .disabled(model.rpkState != .ready || h1IsBusy || model.h1RequiresReconnect)
            }
            if h1IsBusy {
                Button("Hủy H1", role: .cancel) { model.cancelH1() }
            }
            if model.h1RequiresReconnect {
                Text("Cần ngắt kết nối và kết nối lại Band trước khi thử lại.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let metrics = model.lastH1RunRecord?.metrics {
                LabeledContent("Bytes / primitives", value: "\(metrics.bytes) / \(metrics.primitives)")
                LabeledContent("Tổng thời gian", value: "\(metrics.totalMilliseconds) ms")
                LabeledContent("ACK p95", value: metrics.ackP95Milliseconds.map { "\($0) ms" } ?? "—")
                if let export = model.lastH1ExportURL {
                    ShareLink(item: H1LogExport(url: export)) {
                        Text("Export log H1")
                    }
                } else {
                    Button("Export log H1") {}
                        .disabled(true)
                }
                if let directory = model.lastH1RunDirectory {
                    Text(directory.path).font(.caption2).textSelection(.enabled)
                }
            }
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

    private var h1IsBusy: Bool {
        switch model.h1State {
        case .fetching, .preparing, .transferring, .waitingForBand: return true
        case .idle, .displayed, .failed: return false
        }
    }

    private func h1ModeLabel(_ mode: H1TestMode) -> String {
        switch mode {
        case .rasterBaseline: return "Raster · Vietmap Static Map"
        case .rasterOptimized: return "Raster · Indexed PNG"
        case .vectorSynthetic8: return "Vector · Synthetic 8 lines"
        case .vectorSynthetic20: return "Vector · Synthetic 20 lines"
        case .vectorSynthetic40: return "Vector · Synthetic 40 lines"
        case .vectorVietmap: return "Vector · Vietmap TileMap"
        }
    }

    private var h1Label: String {
        switch model.h1State {
        case .idle: return "Sẵn sàng"
        case let .fetching(mode): return "Đang chuẩn bị · \(h1ModeLabel(mode))"
        case let .preparing(mode, runID): return "Band chuẩn bị · \(h1ModeLabel(mode)) · \(runID)"
        case let .transferring(mode, completed, total): return "Đang gửi \(completed)/\(total) · \(h1ModeLabel(mode))"
        case let .waitingForBand(mode, _, sceneID): return "Chờ Band render · \(h1ModeLabel(mode)) · \(sceneID)"
        case let .displayed(mode, _, hashPrefix): return "Đã hiển thị · \(h1ModeLabel(mode)) · \(hashPrefix)"
        case let .failed(mode, code): return "Lỗi \(h1ModeLabel(mode)) · \(code)"
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
