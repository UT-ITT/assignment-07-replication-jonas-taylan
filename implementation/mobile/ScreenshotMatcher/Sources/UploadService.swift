import Foundation
import UIKit

enum UploadError: Error, LocalizedError {
    case noHost
    case imageEncodingFailed
    case matchingFailed(String)
    case badResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .noHost:
            return "Not connected to a host. Wait for discovery or reconnect."
        case .imageEncodingFailed:
            return "Couldn't prepare the photo for sending."
        case .matchingFailed(let message):
            return message.isEmpty ? "The host couldn't match this photo to its screen." : message
        case .badResponse:
            return "The host sent back something unexpected."
        case .network(let error):
            return "Connection problem: \(error.localizedDescription)"
        }
    }
}

/// Sends a captured photo to the Python test script via a multipart/form-data
/// HTTP POST to http://<host>:<port>/upload, and returns the result image the
/// host sends back in the response body.
enum UploadService {
    /// The paper has the phone "scale it down in resolution" before sending.
    /// Skipping this made ORB matching unreliable in practice: full-resolution
    /// iPhone photos (several MB) have keypoint scales that don't line up
    /// well with a much smaller Mac screenshot, so too few good matches were
    /// found. 1280px on the long edge keeps enough detail for feature
    /// matching while shrinking uploads considerably.
    private static let maxDimension: CGFloat = 1280

    static func upload(image: UIImage, host: String, port: UInt16, algorithm: MatchingAlgorithm) async throws -> UIImage {
        let scaledImage = downscaled(image, maxDimension: maxDimension)
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.85) else {
            throw UploadError.imageEncodingFailed
        }

        var components = URLComponents(string: "http://\(host):\(port)/upload")!
        components.queryItems = [URLQueryItem(name: "algorithm", value: algorithm.rawValue)]
        let url = components.url!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UploadError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.badResponse
        }

        if httpResponse.statusCode == 422 {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.matchingFailed(message)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UploadError.badResponse
        }

        guard let resultImage = UIImage(data: data) else {
            throw UploadError.badResponse
        }
        return resultImage
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
