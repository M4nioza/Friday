import Foundation

struct ParsedPlan: Codable {
    let description: String
    let steps: [ParsedStep]
}

struct ParsedStep: Codable {
    let description: String
    let action: [String: AnyCodable]
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}

let json = """
```json
{
  "description": "Go to apple guidelines",
  "steps": [
    {
      "description": "Open Safari to Apple Guidelines",
      "action": {
        "type": "openURL",
        "url": "https://developer.apple.com/design/human-interface-guidelines/"
      }
    },
    {
      "description": "Extract data",
      "action": {
        "type": "extractWebData"
      }
    }
  ]
}
```
"""

var cleanJSON = json.trimmingCharacters(in: .whitespacesAndNewlines)
if cleanJSON.hasPrefix("```json") {
    cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
}
if cleanJSON.hasPrefix("```") {
    cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
}
if cleanJSON.hasSuffix("```") {
    cleanJSON = String(cleanJSON.dropLast(3))
}
cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)

print("Cleaned JSON:")
print(cleanJSON)

let decoder = JSONDecoder()
do {
    let plan = try decoder.decode(ParsedPlan.self, from: cleanJSON.data(using: .utf8)!)
    print("Success: \(plan.description)")
    for step in plan.steps {
        print(" - Step: \(step.description), Action Type: \(step.action["type"]?.value ?? "nil")")
    }
} catch {
    print("Error decoding: \(error)")
}
