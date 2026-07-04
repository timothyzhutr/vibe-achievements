import Foundation

enum TextContent {
    static func extract(from value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            return array.compactMap { item in
                guard let object = item as? [String: Any],
                      let type = object["type"] as? String,
                      type == "text" || type == "input_text" || type == "output_text"
                else { return nil }
                return object["text"] as? String
            }.joined(separator: "\n")
        }
        return ""
    }
}
