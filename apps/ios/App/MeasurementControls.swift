import SwiftUI

struct MeasurementControls: View {
    @ObservedObject var model: AppModel
    let navigationIsActive: Bool

    var body: some View {
        Group {
            TextField("Mã ca đo (ví dụ fg-warm-01)", text: $model.performanceCaseID)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .disabled(navigationIsActive)
            Picker("Nguồn GPS", selection: $model.performanceGPSSource) {
                Text("Chưa chọn").tag(NavigationMeasurement.GPSSource.unknown)
                Text("GPS thiết bị").tag(NavigationMeasurement.GPSSource.device)
                Text("Replay").tag(NavigationMeasurement.GPSSource.replay)
            }.disabled(navigationIsActive)
            Picker("Bản đồ", selection: $model.performanceMapMode) {
                Text("Tự động").tag(NavigationMeasurement.MapMode.automatic)
                Text("Toàn khung (đối chứng)").tag(NavigationMeasurement.MapMode.full)
            }.disabled(navigationIsActive)
            if let measurement = model.activeMeasurement {
                Text("Ca: \(measurement.caseID.isEmpty ? "chưa đặt mã" : measurement.caseID) · \(measurement.mapMode == .automatic ? "tự động" : "toàn khung")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if navigationIsActive && model.performanceTrace.activeSessionID != nil {
                Menu("Đánh dấu đoạn đang thử") {
                    Button("Khởi tạo") { model.markMeasurementPhase(.startup) }
                    Button("Di chuyển đã có bản đồ") { model.markMeasurementPhase(.cached) }
                    Button("Đổi vùng") { model.markMeasurementPhase(.coverage) }
                    Button("Rẽ") { model.markMeasurementPhase(.turn) }
                    Button("Khôi phục") { model.markMeasurementPhase(.recovery) }
                }
                Button("Thấy đứng hình / sai hình") { model.markVisibleProblem() }
                Button("Chụp chẩn đoán trước khi Dừng") { model.capturePerformanceDiagnostics() }
            }
            Text(model.performanceDiagnosticsStatus).font(.caption).foregroundStyle(.secondary)
            Text("Dừng rồi export sau mỗi ca; chỉ giữ 3 phiên gần nhất.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
