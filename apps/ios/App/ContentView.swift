import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BlueBandCore

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: AppModel
    @State private var isConfigPresented = false
    @State private var isBandPickerPresented = false
    @State private var isDebugExportPresented = false

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
                    Text("Active background navigation • motorcycle • raster route-card")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(BlueBandProduct.displayName)
            .toolbar { Button("Cấu hình") { isConfigPresented = true } }
            .sheet(isPresented: $isConfigPresented) { ConfigView(model: model) }
            .sheet(isPresented: $isBandPickerPresented) { BandPickerView(model: model) }
            .fileExporter(
                isPresented: $isDebugExportPresented,
                document: NavigationDebugDocument(text: model.navigationDebugExport),
                contentType: .plainText,
                defaultFilename: "BlueBandMap-navigation-debug.txt"
            ) { _ in }
            .onAppear { model.navigationScreenActive(true) }
            .onDisappear { model.navigationScreenActive(false) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                model.applicationStateChanged(phase == .active ? "active" : phase == .background ? "background" : "inactive")
            }
        }
    }

    private var navigationSection: some View {
        Section("Live Route Card") {
            LabeledContent("Trạng thái", value: navigationLabel)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(model.liveLocationHealth).font(.caption)
            }
            if model.locationNeedsSettings {
                Button("Mở Cài đặt vị trí") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            if let age = model.lastMapFixAgeMilliseconds {
                LabeledContent("GPS → Band", value: "\(age) ms • \(model.latencyViolations) lần ≥5s")
            }
            LabeledContent("Điểm bắt đầu", value: model.navigationStartText)
            LabeledContent("Điểm đến", value: model.navigationDestinationText)
            LabeledContent("Chỉ dẫn", value: instructionLabel)
            LabeledContent("Khoảng cách tới lượt", value: instructionDistanceLabel)
            if !model.navigationStreet.isEmpty { Text(model.navigationStreet) }
            if let distance = model.navigationRouteDistanceMeters {
                LabeledContent(
                    "Tổng tuyến",
                    value: "\(distance) m • \(model.navigationInstructions.count) bước • \(model.navigationAlternativePathCount ?? 1) tuyến nhận được"
                )
            }
            if !model.navigationInstructions.isEmpty {
                DisclosureGroup("Các bước chỉ dẫn") {
                    ForEach(Array(model.navigationInstructions.enumerated()), id: \.offset) { index, instruction in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(instruction.maneuver.rawValue) • \(Int(instruction.distanceMeters.rounded())) m")
                                .font(.subheadline)
                            if !instruction.streetName.isEmpty {
                                Text(instruction.streetName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let data = model.routePreviewPNG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: 212).accessibilityLabel("Bản đồ điều hướng đang hiển thị trên band")
            }
            if navigationIsActive {
                Button("Dừng điều hướng", role: .destructive) { model.stopNavigation() }
            } else {
                Button("Bắt đầu điều hướng") { model.startNavigation() }
                    .disabled(model.rpkState != .ready)
            }
            if !model.navigationDebugEntries.isEmpty {
                Button { isDebugExportPresented = true } label: {
                    Label("Export debug log", systemImage: "square.and.arrow.up")
                }
                DisclosureGroup("Debug log (\(model.navigationDebugEntries.count))") {
                    ForEach(model.navigationDebugEntries, id: \.sequence) { entry in
                        Text("[\(entry.elapsedMilliseconds)ms] #\(entry.sequence) \(entry.stage) \(entry.detail)")
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                }
            }
            Text("Ảnh preview dùng cùng snapshot đã nén và scene với Smart Band.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var instructionLabel: String {
        model.navigationRouteDistanceMeters == nil ? "—" : model.navigationManeuver.rawValue
    }

    private var instructionDistanceLabel: String {
        model.navigationRouteDistanceMeters == nil ? "—" : "\(model.navigationDistanceMeters) m"
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
        case .transferring: "Đang gửi bản đồ"
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

private struct NavigationDebugDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
