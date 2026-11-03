import SwiftUI

/// Point size of file names in the results list. The user changes it with
/// View > Larger Text / Smaller Text, and it is saved in UserDefaults.
enum ResultsTextSize {
    static let key = "ResultsTextSize"
    static let standard: Double = 15
    static let range: ClosedRange<Double> = 11...26

    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct TextSizeCommands: Commands {
    @AppStorage(ResultsTextSize.key) private var textSize = ResultsTextSize.standard

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Larger Text") {
                textSize = ResultsTextSize.clamped(textSize + 1)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(textSize >= ResultsTextSize.range.upperBound)

            Button("Smaller Text") {
                textSize = ResultsTextSize.clamped(textSize - 1)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(textSize <= ResultsTextSize.range.lowerBound)

            Button("Actual Size") {
                textSize = ResultsTextSize.standard
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(textSize == ResultsTextSize.standard)
        }
    }
}
