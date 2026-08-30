import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct H1LogExport: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            contentType: .json,
            exporting: { export in SentTransferredFile(export.url) },
            importing: { received in H1LogExport(url: received.file) }
        )
    }
}

struct H1LogExportLink: View {
    let url: URL

    var body: some View {
        ShareLink(
            item: H1LogExport(url: url),
            preview: SharePreview(url.lastPathComponent)
        ) {
            Text("Export log H1")
        }
    }
}
