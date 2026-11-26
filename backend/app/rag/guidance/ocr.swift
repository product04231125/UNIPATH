// Local macOS Vision OCR. No document content is sent to an external model.
import Foundation
import Vision

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: input))
var output: [[String: Any]] = []
for path in paths {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = true
    do {
        try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> [String: Any]? in
            guard let text = observation.topCandidates(1).first else { return nil }
            return ["text": text.string, "confidence": text.confidence,
                    "box": [observation.boundingBox.minX, observation.boundingBox.minY,
                            observation.boundingBox.width, observation.boundingBox.height]]
        }
        output.append(["path": path, "lines": lines])
    } catch {
        output.append(["path": path, "error": "ocr_failed", "lines": []])
    }
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
