import Foundation
import SotoSignerV4
import Vapor
struct R2Service {
    let signer: AWSSigner?
    let endpoint: String
    let bucket: String
    init(_ r2: Application.R2) {
        self.signer = r2.signer
        self.endpoint = r2.endpoint
        self.bucket = r2.bucket
    }
    enum R2Error: Error {
        case notConfigured
    }
    func objectURL(key: String) throws -> URL {
        let encodedKey = key.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "\(endpoint)/\(bucket)/\(encodedKey)") else {
            throw Abort(.internalServerError, reason: "Could not build object URL for \(key).")
        }
        return url
    }
    func presignedPutURL(key: String, contentType: String? = nil, expiry: TimeInterval = 600) throws -> String {
        guard let signer else { throw R2Error.notConfigured }
        var headers = HTTPHeaders()
        if let contentType { headers.replaceOrAdd(name: "Content-Type", value: contentType) }
        return signer.signURL(
            url: try objectURL(key: key),
            method: .PUT,
            headers: headers,
            expires: .seconds(Int64(expiry))
        ).absoluteString
    }
    func presignedGetURL(key: String, expiry: TimeInterval = 3600) throws -> String {
        guard let signer else { throw R2Error.notConfigured }
        return signer.signURL(
            url: try objectURL(key: key),
            method: .GET,
            expires: .seconds(Int64(expiry))
        ).absoluteString
    }
    func download(key: String, using client: any Client) async throws -> Data {
        let url = try presignedGetURL(key: key)
        let response = try await client.get(URI(string: url))
        guard response.status == .ok else {
            throw Abort(.notFound, reason: "R2 GET \(key) returned \(response.status.code).")
        }
        guard var body = response.body else { return Data() }
        return Data(body.readBytes(length: body.readableBytes) ?? [])
    }
    func upload(key: String, data: Data, contentType: String, using client: any Client) async throws {
        let url = try presignedPutURL(key: key, contentType: contentType)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: "Content-Type", value: contentType)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        let response = try await client.put(URI(string: url), headers: headers) { req in
            req.body = buffer
        }
        guard response.status == .ok || response.status == .created else {
            throw Abort(.internalServerError, reason: "R2 PUT \(key) returned \(response.status.code).")
        }
    }
}
