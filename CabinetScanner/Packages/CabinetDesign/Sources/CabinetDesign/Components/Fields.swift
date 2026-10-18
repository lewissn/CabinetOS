import SwiftUI

/// Underline field: label above, value on a 1 pt rule that turns amber (1.5 pt) when focused.
public struct PaperUnderlineField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let unit: String?
    let keyboard: UIKeyboardType
    let style: PaperType

    @FocusState private var focused: Bool

    public init(_ label: String, text: Binding<String>, placeholder: String = "", unit: String? = nil,
                keyboard: UIKeyboardType = .default, style: PaperType = .body) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.unit = unit
        self.keyboard = keyboard
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            if !label.isEmpty { PaperLabel(label) }
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.s) {
                TextField(placeholder, text: $text)
                    .paperType(style, numeric: keyboard != .default)
                    .foregroundStyle(PaperColor.ink)
                    .keyboardType(keyboard)
                    .focused($focused)
                    .accessibilityLabel(label)
                if let unit {
                    Text(unit).paperType(.subhead).foregroundStyle(PaperColor.secondary)
                }
            }
            .padding(.bottom, PaperSpace.xs)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? PaperColor.accent : PaperColor.dot)
                    .frame(height: focused ? 1.5 : 1)
            }
        }
    }
}

/// Big light numeric entry on a 1.5 pt ink rule (weigh-ins, amounts).
public struct PaperHeroField: View {
    @Binding var text: String
    let unit: String
    let placeholder: String
    let accessibilityLabel: String
    let autofocus: Bool

    @FocusState private var focused: Bool

    public init(text: Binding<String>, unit: String, placeholder: String = "0", accessibilityLabel: String, autofocus: Bool = true) {
        self._text = text
        self.unit = unit
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
        self.autofocus = autofocus
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaperSpace.s) {
            TextField(placeholder, text: $text)
                .paperType(.heroInput, numeric: true)
                .foregroundStyle(PaperColor.ink)
                .keyboardType(.decimalPad)
                .focused($focused)
                .accessibilityLabel(accessibilityLabel)
            Text(unit)
                .font(.brand(18, relativeTo: .title3))
                .foregroundStyle(PaperColor.secondary)
        }
        .padding(.bottom, PaperSpace.xxs)
        .overlay(alignment: .bottom) { Rectangle().fill(PaperColor.ink).frame(height: 1.5) }
        .onAppear {
            if autofocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
        }
    }
}

/// Search field: glyph, text, clear button, underline that turns amber when focused.
public struct PaperSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    public init(text: Binding<String>, prompt: String = "Search") {
        self._text = text
        self.prompt = prompt
    }

    public var body: some View {
        HStack(spacing: 10) {
            PaperIcon(.search, size: 16, color: PaperColor.secondary)
            TextField(prompt, text: $text)
                .paperType(.callout)
                .foregroundStyle(PaperColor.ink)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: { PaperIcon(.close, size: 12, lineWidth: 2, color: PaperColor.secondary) }
                    .frame(width: 32, height: 44)
                    .accessibilityLabel("Clear search")
            }
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(focused ? PaperColor.accent : PaperColor.dot).frame(height: 1) }
    }
}
