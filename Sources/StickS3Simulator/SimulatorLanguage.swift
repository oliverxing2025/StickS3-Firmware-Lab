import Foundation

enum SimulatorLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    func text(_ chinese: String, _ english: String) -> String {
        self == .english ? english : chinese
    }
}

func simulatorText(_ chinese: String, _ english: String, language: String) -> String {
    (SimulatorLanguage(rawValue: language) ?? .chinese).text(chinese, english)
}

func localizedSimulatorMessage(_ message: String, language: String) -> String {
    guard language == SimulatorLanguage.english.rawValue else { return message }

    if message.hasPrefix("已从测试列表移除 "), message.hasSuffix("；原项目未更改") {
        let name = message
            .dropFirst("已从测试列表移除 ".count)
            .dropLast("；原项目未更改".count)
        return "Removed \(name) from the test list; the original project is unchanged"
    }
    if message.hasPrefix("测试项目列表保存失败：") {
        return "Could not save the test project list: "
            + String(message.dropFirst("测试项目列表保存失败：".count))
    }
    let suffixes = [
        "可模拟": "Ready",
        "源码已识别，可自动生成模拟接口": "Recognized; simulator adapter can be generated automatically",
        "仅识别，当前不可模拟": "Recognized; simulation unavailable",
        "不是可识别的 Stick S3 项目": "Unrecognized Stick S3 project",
        "原目录已不存在": "Original folder is missing",
    ]
    for (chinese, english) in suffixes where message.hasSuffix("：" + chinese) {
        return String(message.dropLast(chinese.count)) + english
    }
    return message
}
