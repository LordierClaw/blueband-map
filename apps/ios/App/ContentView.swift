import SwiftUI
import UIKit
import BlueBandCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isConfigPresented = false
    @State private var isBandPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Xiaomi Smart Band 10") {
                    Button("Kết nối") { isBandPickerPresented = true }.disabled(model.sessionState != .idle)
                    LabeledContent("Phiên", value: model.sessionState.rawValue)
                    if model.sessionState != .idle && model.sessionState != .scanning {
                        Button("Ngắt kết nối", role: .destructive) { Task { await model.disconnect() } }
                    }
                }
                Section("Device proof") {
                    LabeledContent("Battery", value: model.snapshot.batteryLevel.map { "\($0)%" } ?? "—")
                    LabeledContent("Model", value: model.snapshot.model ?? "—")
                    LabeledContent("Firmware", value: model.snapshot.firmware ?? "—")
                }
                Section("RPK trust") {
                    LabeledContent("Handshake", value: rpkLabel)
                    Button("Reset trusted fingerprint", role: .destructive) { Task { await model.resetTrustedRPK() } }
                }
                navigationSection
                Section("system.echo") {
                    TextField("Payload", text: $model.echoInput)
                    Button("Gửi echo") { Task { await model.sendEcho() } }.disabled(model.rpkState != .ready)
                    ForEach(model.events) { item in
                        HStack { Text(item.source.rawValue.uppercased()).font(.caption.bold()); Text(item.text); Spacer(); Text(item.delivery.rawValue).font(.caption2) }
                    }
                }
                if let error = model.errorMessage { Section("Lỗi an toàn") { Text(error).foregroundStyle(.red) } }
                Section("Build") {
                    LabeledContent("iOS", value: BlueBandProduct.version)
                    Text("Foreground-only • motorcycle • raster route-card")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(BlueBandProduct.displayName)
            .toolbar { Button("Cấu hình") { isConfigPresented = true } }
            .sheet(isPresented: $isConfigPresented) { ConfigView(model: model) }
            .sheet(isPresented: $isBandPickerPresented) { BandPickerView(model: model) }
        }
    }

    private var navigationSection: some View {
        Section("Live Route Card") {
            LabeledContent("Trạng thái", value: navigationLabel)
            LabeledContent("Chỉ dẫn", value: model.navigationManeuver.rawValue)
            LabeledContent("Khoảng cách", value: "\(model.navigationDistanceMeters) m")
            if !model.navigationStreet.isEmpty { Text(model.navigationStreet) }
            if let data = model.routePreviewPNG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(maxWidth: 212).accessibilityLabel("Route card đang hiển thị trên band")
            }
            if navigationIsActive {
                Button("Dừng điều hướng", role: .destructive) { model.stopNavigation() }
            } else {
                Button("Bắt đầu điều hướng") { model.startNavigation() }
                    .disabled(model.rpkState != .ready)
            }
            Text("Ảnh preview dùng cùng PNG và scene với Smart Band.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var navigationIsActive: Bool {
        switch model.navigationState {
        case .idle, .arrived, .failed: false
        default: true
        }
    }

    private var navigationLabel: String {
        switch model.navigationState {
        case .idle: "Sẵn sàng"
        case .waitingForGPS: "Chờ GPS ≤25 m"
        case .routing: "Đang lấy tuyến"
        case .transferring: "Đang gửi route-card"
        case .navigating: "Đang điều hướng"
        case .gpsLow: "GPS LOW"
        case .limitedMap: "LIMITED MAP"
        case .rerouting: "Đang tính lại tuyến"
        case .arrived: "Đã đến nơi"
        case let .failed(code): code
        }
    }

    private var rpkLabel: String {
        switch model.rpkState {
        case .locked: "Chưa có phiên"
        case .waiting: "Chờ mở app trên band"
        case .ready: "Đã xác thực"
        case let .failed(message): message
        }
    }
}
