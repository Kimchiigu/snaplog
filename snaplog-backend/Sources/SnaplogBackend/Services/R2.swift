import SotoSignerV4
import Vapor
extension Application {
    struct R2 {
        var signer: AWSSigner?
        var endpoint: String { Environment.get("R2_ENDPOINT_URL") ?? "" }
        var bucket: String { Environment.get("R2_BUCKET_NAME") ?? "snaplog-media-dev" }
        init() {
            if let accessKey = Environment.get("R2_ACCESS_KEY_ID"),
               let secretKey = Environment.get("R2_SECRET_ACCESS_KEY") {
                self.signer = AWSSigner(
                    credentials: StaticCredential(accessKeyId: accessKey, secretAccessKey: secretKey),
                    name: "s3",
                    region: "auto"
                )
            } else {
                self.signer = nil
            }
        }
    }
    private struct R2Key: StorageKey {
        typealias Value = R2
    }
    var r2: R2 {
        get { storage[R2Key.self] ?? R2() }
        set { storage[R2Key.self] = newValue }
    }
}
extension Request {
    var r2: Application.R2 { application.r2 }
}
