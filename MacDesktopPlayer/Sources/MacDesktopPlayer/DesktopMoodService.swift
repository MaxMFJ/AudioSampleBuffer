import AppKit
import CryptoKit

struct DesktopMoodColors {
    var atmosphere = SIMD4<Float>(1.0, 0.88, 0.72, 1)
    var volumetricBeam = SIMD4<Float>(1.0, 0.85, 0.65, 1)
    var topLightArray = SIMD4<Float>(0.3, 0.6, 1.0, 1)
    var laserFanBlue = SIMD4<Float>(0.25, 0.55, 1.0, 1)
    var laserFanGreen = SIMD4<Float>(0.35, 1.0, 0.45, 1)
    var rotatingBeam = SIMD4<Float>(1.0, 0.4, 0.8, 1)
    var rotatingBeamExtra = SIMD4<Float>(1.0, 0.5, 0.9, 1)
    var edgeLight = SIMD4<Float>(1.0, 0.75, 0.35, 1)
    var coronaFilaments = SIMD4<Float>(0.9, 0.6, 0.8, 1)
    var pulseRing = SIMD4<Float>(0.8, 0.3, 1.0, 1)

    init() {}

    init(json: [String: Any]) {
        self.init()
        func color(_ key: String, _ fallback: SIMD4<Float>) -> SIMD4<Float> {
            guard let values = json[key] as? [NSNumber], values.count == 3 else { return fallback }
            return SIMD4<Float>(min(max(values[0].floatValue, 0), 1),
                                min(max(values[1].floatValue, 0), 1),
                                min(max(values[2].floatValue, 0), 1), 1)
        }
        atmosphere = color("atmosphere", atmosphere)
        volumetricBeam = color("volumetricBeam", volumetricBeam)
        topLightArray = color("topLightArray", topLightArray)
        laserFanBlue = color("laserFanBlue", laserFanBlue)
        laserFanGreen = color("laserFanGreen", laserFanGreen)
        rotatingBeam = color("rotatingBeam", rotatingBeam)
        rotatingBeamExtra = color("rotatingBeamExtra", rotatingBeamExtra)
        edgeLight = color("edgeLight", edgeLight)
        coronaFilaments = color("coronaFilaments", coronaFilaments)
        pulseRing = color("pulseRing", pulseRing)
    }
}

@MainActor
final class DesktopMoodService {
    static let shared = DesktopMoodService()
    private(set) var colors = DesktopMoodColors()
    private var generation = 0
    private let defaults = UserDefaults.standard

    var baseURL: String { defaults.string(forKey: "DesktopMood.baseURL") ?? "https://api.deepseek.com" }
    var model: String { defaults.string(forKey: "DesktopMood.model") ?? "deepseek-chat" }
    var apiKey: String { defaults.string(forKey: "DesktopMood.apiKey") ?? "" }

    func configure(baseURL: String, model: String, apiKey: String) {
        defaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "DesktopMood.baseURL")
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "DesktopMood.model")
        defaults.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "DesktopMood.apiKey")
    }

    func analyze(title: String, artist: String?) {
        generation += 1
        let requestGeneration = generation
        colors = DesktopMoodColors()
        guard !apiKey.isEmpty else {
            NSLog("[DesktopMood] 未配置 API Key，使用默认配色")
            return
        }
        let cacheKey = "DesktopMood.colors.v2." + SHA256.hash(data: Data("\(model)|\(title)|\(artist ?? "")".utf8)).map { String(format: "%02x", $0) }.joined()
        if let cached = defaults.dictionary(forKey: cacheKey) {
            colors = DesktopMoodColors(json: cached)
            NSLog("[DesktopMood] 命中配色缓存，laserFanBlue RGB=(%.2f, %.2f, %.2f)",
                  colors.laserFanBlue.x, colors.laserFanBlue.y, colors.laserFanBlue.z)
            return
        }
        var components = URLComponents(string: baseURL)
        guard components?.scheme?.lowercased() == "https", components?.host != nil else { return }
        if components?.path.isEmpty == true || components?.path == "/" || components?.path == "/v1" {
            components?.path = "/v1/chat/completions"
        }
        guard let url = components?.url else { return }
        let prompt = "请为歌曲《\(title)》\(artist.map { " - \($0)" } ?? "")设计情绪氛围光。只返回 JSON 对象，包含 colors 对象，字段 atmosphere、volumetricBeam、topLightArray、laserFanBlue、laserFanGreen、rotatingBeam、rotatingBeamExtra、edgeLight、coronaFilaments、pulseRing；每个字段为 0 到 1 的 RGB 三元素数组。让颜色贴合歌曲情绪，主色与鼓点强调色有清楚区别。laserFanBlue 是字段名而非固定蓝色限制：请按歌曲情绪选择有明显辨识度的高饱和色相，可以是青、紫、洋红、红橙或其他颜色，不要每首歌都返回相近的蓝色。深空蜂巢的吉他颜色波依次使用 pulseRing、coronaFilaments、volumetricBeam、rotatingBeam；请让这四种颜色形成符合歌曲情绪的色组，彼此有清晰区分，并避免所有歌曲都落在同一组紫/蓝色。"
        let payload: [String: Any] = ["model": model, "messages": [
            ["role": "system", "content": "你是音乐舞台灯光设计师。只输出有效 JSON。"],
            ["role": "user", "content": prompt]
        ], "temperature": 0.7, "max_tokens": 600]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 25
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = envelope["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
                      let json = try JSONSerialization.jsonObject(with: Data(content[start...end].utf8)) as? [String: Any],
                      let colorJSON = json["colors"] as? [String: Any] else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    NSLog("[DesktopMood] 配色响应不可用，HTTP 状态码：%d", status)
                    return
                }
                guard requestGeneration == generation else { return }
                defaults.set(colorJSON, forKey: cacheKey)
                colors = DesktopMoodColors(json: colorJSON)
                NSLog("[DesktopMood] 已载入 LLM 配色，laserFanBlue RGB=(%.2f, %.2f, %.2f)",
                      colors.laserFanBlue.x, colors.laserFanBlue.y, colors.laserFanBlue.z)
            } catch {
                NSLog("[DesktopMood] 配色请求失败：%@", error.localizedDescription)
            }
        }
    }
}
