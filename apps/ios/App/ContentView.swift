import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BlueBandCore
import BlueBandMapCore

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: AppModel
    @State private var isConfigPresented = false
    @State private var isBandPickerPresented = false
    @State private var isDebugExportPresented = false
    @State private var isTraceExportPresented = false
    @State private var traceData = Data()
    @State private var traceExportError: String?
    @State private var isPreparingTrace = false

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
            .fileExporter(isPresented: $isTraceExportPresented,
                document: PerformanceTraceDocument(data: traceData),
                contentType: .performanceTrace, defaultFilename: "navigation.jsonl") { result in
                    if case .failure = result { traceExportError = "Không lưu được trace. Hãy thử export lại." }
                    traceData = Data()
                }
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
                LabeledContent("GPS → Band", value: "\(age) ms • \(model.latencyViolations) lần ≥1s")
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
            if let preview = model.routePreviewTiles {
                CorridorPreviewView(viewport: preview.viewport, images: preview.images)
            } else if let data = model.routePreviewPNG, let image = UIImage(data: data) {
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
            Toggle("Đo hiệu năng", isOn: $model.performanceEnabled).disabled(navigationIsActive)
            Toggle("Hiện số khung khi quay video", isOn: $model.performanceVisualMarker).disabled(navigationIsActive)
            Menu {
                Button("Log tóm tắt (.txt)") { isDebugExportPresented = true }
                    .disabled(model.navigationDebugEntries.isEmpty)
                Button("Performance trace (.jsonl)") {
                    isPreparingTrace = true
                    Task {
                        do {
                            traceData = try await model.performanceTrace.export()
                            if traceData.isEmpty { traceExportError = "Chưa có phiên đo được lưu." }
                            else { traceExportError = nil; isTraceExportPresented = true }
                        } catch { traceExportError = "Không đọc được trace đầy đủ. Không dùng log này để kết luận đạt." }
                        isPreparingTrace = false
                    }
                }
            } label: { Label("Export debug log", systemImage: "square.and.arrow.up") }
                .disabled(isPreparingTrace)
            if isPreparingTrace { ProgressView("Đang chuẩn bị trace…") }
            if let traceExportError { Text(traceExportError).foregroundStyle(.red) }
            if !model.navigationDebugEntries.isEmpty {
                DisclosureGroup("Debug log (\(model.navigationDebugEntries.count))") {
                    ForEach(model.navigationDebugEntries, id: \.sequence) { entry in
                        Text("[\(entry.elapsedMilliseconds)ms] #\(entry.sequence) \(entry.stage) \(entry.detail)")
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                }
            }
            Text("Preview dùng cùng ảnh và vị trí map đã xác nhận trên Band.")
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

struct CorridorPreviewView: View {
    let viewport: CorridorViewport
    let images: [CorridorCell: UIImage]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(viewport.visibleCells, id: \.key) { cell in
                if let image = images[cell] {
                    Image(uiImage: image).resizable().interpolation(.high)
                        .frame(width: 128, height: 128)
                        .offset(x: CGFloat(cell.column * 128 + viewport.x), y: CGFloat(cell.row * 128 + viewport.y))
                }
            }
        }
        .frame(width: 212, height: 520, alignment: .topLeading).clipped()
        .overlay {
            Text("© Vietmap").font(.system(size: 9))
                .foregroundStyle(Color(red: 244 / 255, green: 243 / 255, blue: 229 / 255))
                .position(x: 106, y: 490)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bản đồ điều hướng đang hiển thị trên band")
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

private extension UTType {
    static let performanceTrace = UTType(filenameExtension: "jsonl", conformingTo: .plainText) ?? .plainText
}

private struct PerformanceTraceDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.performanceTrace]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
