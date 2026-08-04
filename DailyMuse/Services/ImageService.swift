import Foundation

/// Supported image generation endpoint types.
enum ImageEndpointType: String, CaseIterable, Identifiable {
    /// OpenAI-compatible /v1/images/generations — returns base64 or URL.
    /// Works with: OpenAI DALL-E, FAL.ai, Stability AI (via proxy), etc.
    case openAICompatible

    /// MFlux / Krea2 / generic local server that accepts a JSON body
    /// and returns raw PNG bytes directly.
    case localDirect

    /// ComfyUI API — queue a workflow and poll for results.
    case comfyUI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .localDirect: "Local Direct (MFlux/Krea2)"
        case .comfyUI: "ComfyUI"
        }
    }
}

/// Generates images via configurable HTTP endpoints.
struct ImageService {
    let baseURL: String
    let endpointType: ImageEndpointType
    var apiKey: String?

    func generate(prompt: String, width: Int, height: Int) async throws -> Data {
        switch endpointType {
        case .openAICompatible:
            return try await generateOpenAI(prompt: prompt, width: width, height: height)
        case .localDirect:
            return try await generateLocalDirect(prompt: prompt, width: width, height: height)
        case .comfyUI:
            return try await generateComfyUI(prompt: prompt, width: width, height: height)
        }
    }

    // MARK: - OpenAI-compatible

    private func generateOpenAI(prompt: String, width: Int, height: Int) async throws -> Data {
        let endpoint = baseURL.trimmingSuffix("/") + "/v1/images/generations"
        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        let body: [String: Any] = [
            "prompt": prompt,
            "n": 1,
            "size": "\(width)x\(height)",
            "response_format": "b64_json"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

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
        request.timeoutInterval = 600

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        // Verify we got image data (PNG magic bytes)
        guard data.count > 8,
              data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 else {
            // Maybe it's JSON-wrapped base64
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let b64 = json["image"] as? String,
               let imgData = Data(base64Encoded: b64) {
                return imgData
            }
            throw DailyMuseError.imageError("Response is not a valid PNG")
        }

        return data
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
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promptID = json["prompt_id"] as? String else {
            throw DailyMuseError.imageError("ComfyUI did not return a prompt_id")
        }

        // Poll for completion
        let historyURL = URL(string: baseURL.trimmingSuffix("/") + "/history/\(promptID)")!
        for _ in 0..<120 { // up to 10 minutes
            try await Task.sleep(for: .seconds(5))

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

        throw DailyMuseError.imageError("ComfyUI generation timed out")
    }

    // MARK: - Helpers

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DailyMuseError.imageError("HTTP \(code): \(body)")
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
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
