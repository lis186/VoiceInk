import Foundation

/// Converts Simplified Chinese characters to Traditional Chinese using OpenCC's
/// STCharacters.txt (Apache 2.0), loaded from the app bundle at runtime.
/// English characters, punctuation, and characters shared between SC/TC are unaffected.
enum ChineseConverter {

    static func simplifiedToTraditional(_ text: String) -> String {
        return String(text.unicodeScalars.map { scalar in
            let c = Character(scalar)
            return mapping[c] ?? c
        })
    }

    // Loaded once from Resources/STCharacters.txt in the app bundle.
    private static let mapping: [Character: Character] = {
        guard let url = Bundle.main.url(forResource: "STCharacters", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var dict = [Character: Character]()
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            // Skip comment lines
            guard !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let sc = parts[0].first else { continue }
            // Value field may contain multiple space-separated alternatives; take the first.
            let firstTC = parts[1].split(separator: " ", maxSplits: 1).first
            guard let tc = firstTC?.first else { continue }
            dict[sc] = tc
        }
        return dict
    }()
}
