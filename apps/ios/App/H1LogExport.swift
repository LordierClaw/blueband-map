import CoreTransferable
import Foundation
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
