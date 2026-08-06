import Foundation

/// Supported image generation endpoint types.
enum ImageEndpointType: String, CaseIterable, Identifiable {
    /// OpenAI-compatible /v1/images/generations — returns base64 or URL.
    /// Works with: OpenAI DALL-E, FAL.ai, Stability AI (via proxy), etc.
    case openAICompatible

    /// MFlux / Krea2 / generic local server that accepts a JSON body
    /// and returns raw PNG bytes directly.
    case localDirect

    /// Generic queued server: POST /generate returns JSON with a job/status/result URL,
    /// then the client polls until final image data or an image URL is available.
    case queuedGenerate

    /// fal.ai queue API — submit to queue.fal.run/{model}, poll status_url,
    /// then fetch response_url and download images[0].url.
    case falQueue

    /// ComfyUI API — queue a workflow and poll for results.
    case comfyUI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .localDirect: "Direct /generate"
        case .queuedGenerate: "Queued /generate"
        case .falQueue: "fal.ai Queue"
        case .comfyUI: "ComfyUI"
        }
    }

    var contractDescription: String {
        switch self {
        case .openAICompatible:
            "POST /v1/images/generations and expect b64_json or image URL in the response."
        case .localDirect:
            "POST /generate and expect the final PNG/base64/image URL in the same response."
        case .queuedGenerate:
            "POST /generate, read a job/status/result URL from JSON, then poll for the finished image."
        case .falQueue:
            "POST queue.fal.run/{model}, poll fal status_url, fetch response_url, then download images[0].url."
        case .comfyUI:
            "POST /prompt, poll /history/{prompt_id}, then download the image from /view."
        }
    }
}

enum ImageResponseFormat: String, CaseIterable, Identifiable {
    case b64JSON = "b64_json"
    case url

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .b64JSON: "Base64 JSON"
        case .url: "Download URL"
        }
    }
}

/// Generates images via configurable HTTP endpoints.
struct ImageService {
    let baseURL: String
    let endpointType: ImageEndpointType
    let timeoutSeconds: TimeInterval
    let imageModel: String
    let responseFormat: ImageResponseFormat
    var apiKey: String?

    init(
        baseURL: String,
        endpointType: ImageEndpointType,
        timeoutSeconds: TimeInterval = 3600,
        imageModel: String = "krea-2",
        responseFormat: ImageResponseFormat = .b64JSON
    ) {
        self.baseURL = baseURL
        self.endpointType = endpointType
        self.timeoutSeconds = timeoutSeconds
        self.imageModel = imageModel
        self.responseFormat = responseFormat
    }

    func generate(prompt: String, width: Int, height: Int) async throws -> Data {
        switch endpointType {
        case .openAICompatible:
            return try await generateOpenAI(prompt: prompt, width: width, height: height)
        case .localDirect:
            return try await generateLocalDirect(prompt: prompt, width: width, height: height)
        case .queuedGenerate:
            return try await generateQueued(prompt: prompt, width: width, height: height)
        case .falQueue:
            return try await generateFalQueue(prompt: prompt, width: width, height: height)
        case .comfyUI:
            return try await generateComfyUI(prompt: prompt, width: width, height: height)
        }
    }

    func testEndpoint() async throws {
        let endpoint: String
        switch endpointType {
        case .openAICompatible:
            endpoint = baseURL.trimmingSuffix("/") + "/v1/images/generations"
        case .localDirect, .queuedGenerate:
            endpoint = baseURL.trimmingSuffix("/") + "/generate"
        case .falQueue:
            endpoint = falEndpoint
        case .comfyUI:
            endpoint = baseURL.trimmingSuffix("/") + "/prompt"
        }

        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 15
        if let authorizationHeaderValue {
            request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DailyMuseError.imageError("No HTTP response from \(endpoint)")
        }

        if (200...499).contains(http.statusCode) {
            return
        }

        let body = String(data: data, encoding: .utf8) ?? "no body"
        throw DailyMuseError.imageError("Endpoint \(endpoint) returned HTTP \(http.statusCode): \(body)")
    }

    // MARK: - OpenAI-compatible

    private func generateOpenAI(prompt: String, width: Int, height: Int) async throws -> Data {
        let endpoint = baseURL.trimmingSuffix("/") + "/v1/images/generations"
        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        var body: [String: Any] = [
            "prompt": prompt,
            "n": 1,
            "size": "\(width)x\(height)",
            "response_format": responseFormat.rawValue
        ]
        if !imageModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["model"] = imageModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorizationHeaderValue {
            request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["data"] as? [[String: Any]],
              let b64 = results.first?["b64_json"] as? String,
              let imageData = Data(base64Encoded: b64) else {
            // Try URL fallback
            if let results = json?["data"] as? [[String: Any]],
               let urlString = results.first?["url"] as? String,
               let imageURL = URL(string: urlString) {
                let (imgData, _) = try await URLSession.shared.data(from: imageURL)
                return imgData
            }
            throw DailyMuseError.imageError("Could not decode image from response")
        }

        return imageData
    }

    // MARK: - Local Direct (POST prompt → get PNG bytes)

    /// Simple endpoint: POST JSON with "prompt", "width", "height" → response body is raw PNG.
    /// Adapt the request body shape to match your local server.
    private func generateLocalDirect(prompt: String, width: Int, height: Int) async throws -> Data {
        let endpoint = baseURL.trimmingSuffix("/") + "/generate"
        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        let body: [String: Any] = [
            "prompt": prompt,
            "width": width,
            "height": height,
            "num_inference_steps": 9,
            "seed": Int.random(in: 0...999999)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        // Verify we got image data (PNG magic bytes)
        if let imageData = try await imageData(from: data) {
            return imageData
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           queuedJob(from: json) != nil {
            throw DailyMuseError.imageError("Server returned a queued job. Select the Queued /generate endpoint type so DailyMuse can poll for the finished image.")
        }

        throw DailyMuseError.imageError("Response did not contain final image data. Use Queued /generate if this server returns jobs instead of images.")
    }

    // MARK: - Queued /generate

    private func generateQueued(prompt: String, width: Int, height: Int) async throws -> Data {
        let endpoint = baseURL.trimmingSuffix("/") + "/generate"
        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        let body: [String: Any] = [
            "prompt": prompt,
            "width": width,
            "height": height,
            "num_inference_steps": 9,
            "seed": Int.random(in: 0...999999)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        if let imageData = try await imageData(from: data) {
            return imageData
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let job = queuedJob(from: json) else {
            throw DailyMuseError.imageError("Queued server did not return image data, a status URL, a result URL, or a job id.")
        }

        if let resultURL = job.resultURL {
            return try await downloadImage(from: resultURL)
        }

        guard let statusURL = job.statusURL else {
            throw DailyMuseError.imageError("Queued server returned a job id but no status URL. DailyMuse tried /status/{id}; configure the server to return status_url or result_url.")
        }

        for _ in 0..<pollAttempts {
            try await Task.sleep(for: .seconds(pollIntervalSeconds))

            let (statusData, statusResponse) = try await URLSession.shared.data(from: statusURL)
            try validateHTTPResponse(statusResponse, data: statusData)

            if let imageData = try await imageData(from: statusData) {
                return imageData
            }

            guard let statusJSON = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any] else {
                continue
            }

            if let resultURL = firstURL(in: statusJSON, keys: ["result_url", "resultUrl", "image_url", "imageUrl", "url", "output_url", "outputUrl"]) {
                return try await downloadImage(from: resultURL)
            }

            if let status = firstString(in: statusJSON, keys: ["status", "state"])?.lowercased() {
                if ["failed", "failure", "error", "canceled", "cancelled"].contains(status) {
                    let message = firstString(in: statusJSON, keys: ["error", "message", "detail"]) ?? status
                    throw DailyMuseError.imageError("Queued generation failed: \(message)")
                }
            }
        }

        throw DailyMuseError.imageError("Queued generation timed out after \(timeoutMinutes) minutes before a finished image was available.")
    }

    // MARK: - fal.ai Queue

    private func generateFalQueue(prompt: String, width: Int, height: Int) async throws -> Data {
        guard let url = URL(string: falEndpoint) else {
            throw DailyMuseError.invalidURL(falEndpoint)
        }

        let body: [String: Any] = [
            "prompt": prompt,
            "image_size": [
                "width": width,
                "height": height
            ],
            "num_images": 1,
            "output_format": "png"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(Int(timeoutSeconds)), forHTTPHeaderField: "X-Fal-Request-Timeout")
        if let authorizationHeaderValue {
            request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let submitJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusURL = firstURL(in: submitJSON, keys: ["status_url", "statusUrl"]) else {
            throw DailyMuseError.imageError("fal.ai did not return a status_url.")
        }

        let initialResponseURL = firstURL(in: submitJSON, keys: ["response_url", "responseUrl"])

        for _ in 0..<pollAttempts {
            try await Task.sleep(for: .seconds(pollIntervalSeconds))

            var statusRequest = URLRequest(url: statusURL)
            statusRequest.setValue("1", forHTTPHeaderField: "logs")
            if let authorizationHeaderValue {
                statusRequest.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            }

            let (statusData, statusResponse) = try await URLSession.shared.data(for: statusRequest)
            try validateHTTPResponse(statusResponse, data: statusData)

            guard let statusJSON = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                  let status = firstString(in: statusJSON, keys: ["status"]) else {
                continue
            }

            if status == "COMPLETED" {
                guard let responseURL = firstURL(in: statusJSON, keys: ["response_url", "responseUrl"]) ?? initialResponseURL else {
                    throw DailyMuseError.imageError("fal.ai completed but did not provide a response_url.")
                }

                return try await fetchFalResult(from: responseURL)
            }

            if let error = firstString(in: statusJSON, keys: ["error", "message", "detail"]) {
                throw DailyMuseError.imageError("fal.ai generation failed: \(error)")
            }
        }

        throw DailyMuseError.imageError("fal.ai generation timed out after \(timeoutMinutes) minutes.")
    }

    private func fetchFalResult(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        if let authorizationHeaderValue {
            request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        if let imageData = try await imageData(from: data) {
            return imageData
        }

        throw DailyMuseError.imageError("fal.ai response did not include an image URL or image data.")
    }

    // MARK: - ComfyUI (queue + poll)

    private func generateComfyUI(prompt: String, width: Int, height: Int) async throws -> Data {
        // ComfyUI uses workflow-based generation. This is a minimal implementation
        // that queues a text2img workflow and polls for the result.
        // Users with custom workflows would extend this.

        let queueURL = URL(string: baseURL.trimmingSuffix("/") + "/prompt")!

        // Minimal text2img workflow — users should customize this
        let workflow = ComfyUIWorkflow.text2img(prompt: prompt, width: width, height: height)

        var request = URLRequest(url: queueURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(workflow)
        request.timeoutInterval = timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promptID = json["prompt_id"] as? String else {
            throw DailyMuseError.imageError("ComfyUI did not return a prompt_id")
        }

        // Poll for completion
        let historyURL = URL(string: baseURL.trimmingSuffix("/") + "/history/\(promptID)")!
        for _ in 0..<pollAttempts {
            try await Task.sleep(for: .seconds(pollIntervalSeconds))

            let (histData, _) = try await URLSession.shared.data(from: historyURL)
            guard let histJSON = try JSONSerialization.jsonObject(with: histData) as? [String: Any],
                  let entry = histJSON[promptID] as? [String: Any],
                  let outputs = entry["outputs"] as? [String: Any] else {
                continue
            }

            // Find the first image output
            for (_, nodeOutput) in outputs {
                guard let nodeDict = nodeOutput as? [String: Any],
                      let images = nodeDict["images"] as? [[String: Any]],
                      let firstImage = images.first,
                      let filename = firstImage["filename"] as? String,
                      let subfolder = firstImage["subfolder"] as? String else {
                    continue
                }

                var components = URLComponents(string: baseURL.trimmingSuffix("/") + "/view")!
                components.queryItems = [
                    URLQueryItem(name: "filename", value: filename),
                    URLQueryItem(name: "subfolder", value: subfolder),
                    URLQueryItem(name: "type", value: "output")
                ]
                let (imgData, _) = try await URLSession.shared.data(from: components.url!)
                return imgData
            }
        }

        throw DailyMuseError.imageError("ComfyUI generation timed out after \(timeoutMinutes) minutes")
    }

    // MARK: - Helpers

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DailyMuseError.imageError("HTTP \(code): \(body)")
        }
    }

    private var pollIntervalSeconds: Int {
        5
    }

    private var pollAttempts: Int {
        max(1, Int(timeoutSeconds) / pollIntervalSeconds)
    }

    private var timeoutMinutes: Int {
        max(1, Int(timeoutSeconds / 60))
    }

    private func imageData(from data: Data) async throws -> Data? {
        if data.isPNG {
            return data
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let b64 = firstString(in: json, keys: ["image", "b64_json", "base64", "data"]),
           let imageData = imageData(fromBase64: b64) {
            return imageData
        }

        if let results = json["data"] as? [[String: Any]] {
            for result in results {
                if let b64 = firstString(in: result, keys: ["b64_json", "image", "base64"]),
                   let imageData = imageData(fromBase64: b64) {
                    return imageData
                }

                if let imageURL = firstURL(in: result, keys: ["url", "image_url", "imageUrl"]) {
                    return try await downloadImage(from: imageURL)
                }
            }
        }

        if let images = json["images"] as? [[String: Any]] {
            for image in images {
                if let b64 = firstString(in: image, keys: ["b64_json", "image", "base64", "data"]),
                   let imageData = imageData(fromBase64: b64) {
                    return imageData
                }

                if let imageURL = firstURL(in: image, keys: ["url", "image_url", "imageUrl"]) {
                    return try await downloadImage(from: imageURL)
                }
            }
        }

        if let imageURL = firstURL(in: json, keys: ["url", "image_url", "imageUrl", "result_url", "resultUrl", "output_url", "outputUrl"]) {
            return try await downloadImage(from: imageURL)
        }

        return nil
    }

    private func imageData(fromBase64 value: String) -> Data? {
        let stripped = value.components(separatedBy: ",").last ?? value
        return Data(base64Encoded: stripped)
    }

    private func downloadImage(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, data: data)
        guard data.isPNG || NSURLConnection.canHandle(URLRequest(url: url)) else {
            return data
        }
        return data
    }

    private func queuedJob(from json: [String: Any]) -> QueuedJob? {
        let statusURL = firstURL(in: json, keys: ["status_url", "statusUrl", "poll_url", "pollUrl"])
        let resultURL = firstURL(in: json, keys: ["result_url", "resultUrl", "image_url", "imageUrl", "output_url", "outputUrl"])

        if statusURL != nil || resultURL != nil {
            return QueuedJob(statusURL: statusURL, resultURL: resultURL)
        }

        guard let jobID = firstString(in: json, keys: ["id", "job_id", "jobId", "request_id", "requestId", "prediction_id", "predictionId"]) else {
            return nil
        }

        let statusEndpoint = baseURL.trimmingSuffix("/") + "/status/\(jobID)"
        return QueuedJob(statusURL: URL(string: statusEndpoint), resultURL: nil)
    }

    private func firstString(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func firstURL(in json: [String: Any], keys: [String]) -> URL? {
        guard let value = firstString(in: json, keys: keys) else {
            return nil
        }

        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        return URL(string: value, relativeTo: URL(string: baseURL.trimmingSuffix("/") + "/"))?.absoluteURL
    }

    private var authorizationHeaderValue: String? {
        guard let key = apiKey, !key.isEmpty else {
            return nil
        }

        switch endpointType {
        case .falQueue:
            return "Key \(key)"
        case .openAICompatible, .localDirect, .queuedGenerate, .comfyUI:
            return "Bearer \(key)"
        }
    }

    private var falEndpoint: String {
        let host = baseURL.trimmingSuffix("/").isEmpty ? "https://queue.fal.run" : baseURL.trimmingSuffix("/")
        let model = imageModel.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("/")
        return host + "/" + model
    }
}

private struct QueuedJob {
    let statusURL: URL?
    let resultURL: URL?
}

private extension Data {
    var isPNG: Bool {
        count > 8 && self[0] == 0x89 && self[1] == 0x50 && self[2] == 0x4E && self[3] == 0x47
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

// MARK: - ComfyUI Workflow Helper

private enum ComfyUIWorkflow {
    struct Prompt: Encodable {
        let prompt: [String: Node]
    }

    struct Node: Encodable {
        let class_name: String
        let inputs: [String: AnyCodable]

        enum CodingKeys: String, CodingKey {
            case class_name = "class_name"
            case inputs
        }
    }

    static func text2img(prompt: String, width: Int, height: Int) -> Prompt {
        // Minimal CheckpointLoaderSimple → CLIPTextEncode → KSampler → VAEDecode → SaveImage
        // Users with real ComfyUI setups would replace this with their own workflow JSON.
        Prompt(prompt: [
            "3": Node(class_name: "KSampler", inputs: [
                "seed": AnyCodable(Int.random(in: 0...999999)),
                "steps": AnyCodable(20),
                "cfg": AnyCodable(7.0),
                "sampler_name": AnyCodable("euler"),
                "scheduler": AnyCodable("normal"),
                "denoise": AnyCodable(1.0),
                "model": AnyCodable(["4", 0]),
                "positive": AnyCodable(["6", 0]),
                "negative": AnyCodable(["7", 0]),
                "latent_image": AnyCodable(["5", 0])
            ]),
            "4": Node(class_name: "CheckpointLoaderSimple", inputs: [
                "ckpt_name": AnyCodable("model.safetensors")
            ]),
            "5": Node(class_name: "EmptyLatentImage", inputs: [
                "width": AnyCodable(width),
                "height": AnyCodable(height),
                "batch_size": AnyCodable(1)
            ]),
            "6": Node(class_name: "CLIPTextEncode", inputs: [
                "text": AnyCodable(prompt),
                "clip": AnyCodable(["4", 1])
            ]),
            "7": Node(class_name: "CLIPTextEncode", inputs: [
                "text": AnyCodable(""),
                "clip": AnyCodable(["4", 1])
            ]),
            "8": Node(class_name: "VAEDecode", inputs: [
                "samples": AnyCodable(["3", 0]),
                "vae": AnyCodable(["4", 2])
            ]),
            "9": Node(class_name: "SaveImage", inputs: [
                "filename_prefix": AnyCodable("DailyMuse"),
                "images": AnyCodable(["8", 0])
            ])
        ])
    }
}

// MARK: - AnyCodable helper for JSON flexibility

struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [Any]: try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try container.encode(v.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
