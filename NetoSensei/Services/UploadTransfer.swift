import Foundation

/// Counts transmitted body bytes, rather than assuming the entire requested body was sent.
enum UploadTransfer {
    final class Receipt: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var sent: Int64 = 0
        var bodyBytesSent: Int64 { lock.lock(); defer { lock.unlock() }; return sent }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            lock.lock(); sent = max(sent, totalBytesSent); lock.unlock()
        }
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static func perform(session: URLSession, request: URLRequest) async throws -> (URLResponse, Int64) {
        let receipt = Receipt()
        let (_, response) = try await session.data(for: request, delegate: receipt)
        return (response, receipt.bodyBytesSent)
    }
}
