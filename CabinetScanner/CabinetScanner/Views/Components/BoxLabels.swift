import CabinetDesign
import SwiftUI

// MARK: - 4×6" box labels
//
// Printed on a direct-thermal printer: black only, no greys that dither into
// noise and no large solid fills (they print faded), heavy rules, and the things a driver and a packer look for read from
// arm's length — who it's for, which box, how it's going.
//
// Drawn at 288 × 432 pt (4 × 6 in at 72 pt). Fixed type sizes: a label must
// look the same whatever the device's text size is set to.

struct BoxLabel: View {
    /// "Hannah Wright"
    let customer: String
    /// "SO 9731", "29248" — whatever identifies the job on this consignment.
    let reference: String?
    /// "Panel box", "Fitting kit box"
    let boxKind: String
    let boxNumber: Int
    /// Known only when every box is printed together.
    var boxCount: Int?
    /// "14 panels", "800 × 200 × 200 mm · 5 kg"
    let contents: String?
    /// "APC", "BJS"
    let courier: String?
    var date: Date = .now

    private let ink = Color.black

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo and the box number, the two things found first.
            HStack(alignment: .top) {
                Image("CabinetLogo")
                    .resizable()
                    .scaledToFit()
                    .grayscale(1)
                    .contrast(1.6)
                    .frame(height: 38)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: -6) {
                    Text("BOX")
                        .font(.brandFixed(11, .semibold))
                        .tracking(1.5)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(boxNumber)")
                            .font(.brandFixed(56, .semibold))
                            .monospacedDigit()
                        if let boxCount {
                            Text("of \(boxCount)")
                                .font(.brandFixed(16, .semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }

            rule(3).padding(.top, 6)

            // Who it's for.
            VStack(alignment: .leading, spacing: 4) {
                Text("FOR")
                    .font(.brandFixed(10, .semibold))
                    .tracking(1.5)
                Text(customer)
                    .font(.brandFixed(30, .semibold))
                    .tracking(-0.6)
                    .lineLimit(3)
                    .minimumScaleFactor(0.55)
                    .fixedSize(horizontal: false, vertical: true)
                if let reference, !reference.isEmpty {
                    Text(reference)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 10)

            // What's inside, in a heavy outline. Black text on white rather
            // than reversed out: thermal heads fade large solid areas, and
            // white type in a faded box is the first thing to go unreadable.
            VStack(alignment: .leading, spacing: 2) {
                Text(boxKind.uppercased())
                    .font(.brandFixed(19, .semibold))
                    .tracking(1)
                if let contents, !contents.isEmpty {
                    Text(contents)
                        .font(.brandFixed(15, .semibold))
                        .monospacedDigit()
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ink, lineWidth: 3))

            // How it's going.
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("VIA")
                        .font(.brandFixed(10, .semibold))
                        .tracking(1.5)
                    Text((courier?.isEmpty == false ? courier! : "–").uppercased())
                        .font(.brandFixed(36, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("PACKED")
                        .font(.brandFixed(10, .semibold))
                        .tracking(1.5)
                    Text(Self.dateFormatter.string(from: date))
                        .font(.brandFixed(14, .semibold))
                        .monospacedDigit()
                }
            }
            .padding(.top, 12)

            rule(1.5).padding(.top, 10)

            HStack {
                Text("Handle with care · This way up ↑")
                Spacer(minLength: 4)
                Text("thecabinetshop.co.uk")
            }
            .font(.brandFixed(8.5, .medium))
            .lineLimit(1)
            .padding(.top, 6)
        }
        .foregroundStyle(ink)
        .padding(16)
        .frame(width: LabelPrinter.pageSize.width, height: LabelPrinter.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func rule(_ weight: CGFloat) -> some View {
        Rectangle().fill(ink).frame(height: weight)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}

extension BoxLabel {
    /// Split "Hannah Wright - #12740" into the customer and the reference, the
    /// way courier consignments are named at the bench.
    static func splitName(_ name: String) -> (customer: String, reference: String?) {
        for separator in [" - #", " – #", " - ", " – "] {
            if let range = name.range(of: separator, options: .backwards) {
                let customer = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let ref = String(name[range.lowerBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -–"))
                if !customer.isEmpty, !ref.isEmpty { return (customer, ref) }
            }
        }
        return (name, nil)
    }
}
