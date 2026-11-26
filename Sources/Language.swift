import Foundation

enum InterfaceLanguage: String {
    case chinese = "zh"
    case english = "en"

    static let preference = "interfaceLanguage"
    static var current: InterfaceLanguage {
        if let value = UserDefaults.standard.string(forKey: preference),
           let saved = InterfaceLanguage(rawValue: value) { return saved }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }
}

// Keep both forms until display: a change of language can happen during a slice read.
struct UIString {
    let zh: String
    let en: String
    init(_ zh: String, _ en: String) { self.zh = zh; self.en = en }
    init(verbatim value: String) { self.init(value, value) }
    init(error: Error) {
        self = (error as? PreviewError)?.message ?? UIString(verbatim: error.localizedDescription)
    }
    var value: String { InterfaceLanguage.current == .chinese ? zh : en }
    var payload: [String:String] { ["zh": zh, "en": en] }
    func appending(_ other: UIString, separator: String) -> UIString {
        UIString(zh + separator + other.zh, en + separator + other.en)
    }
}
