import Foundation

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, locale: Locale.current, arguments: arguments)
}

func LP(_ key: String, _ count: Int, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(
        forKey: key + (count == 1 ? ".one" : ".other"), value: nil, table: nil)
    return String(format: format, locale: Locale.current, arguments: [count] + arguments)
}
