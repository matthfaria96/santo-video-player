import SwiftUI

/// The look of every Settings page, as in MacDash (and macOS System Settings):
/// one level of grouped rows, text first, native controls, quiet footers.
enum SettingsStyle {
    static let columnWidth: CGFloat = 600
    static let sectionSpacing: CGFloat = 26
    static let corner: CGFloat = 12
    static let rowFill = Color.white.opacity(0.055)
    static let rowStroke = Color.white.opacity(0.06)
    static let separator = Color.white.opacity(0.08)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.5)
}

/// A scrolling column of sections, centered with room to breathe.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) { content }
                .frame(maxWidth: SettingsStyle.columnWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
    }
}

/// A titled group of rows with an optional footer.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    var plain = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsStyle.primary)
                .padding(.horizontal, 4)
            if plain {
                content
            } else {
                VStack(spacing: 0) { content }
                    .background(SettingsStyle.rowFill,
                                in: RoundedRectangle(cornerRadius: SettingsStyle.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: SettingsStyle.corner, style: .continuous)
                        .strokeBorder(SettingsStyle.rowStroke, lineWidth: 0.5))
            }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One line: what it is on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
    }
}

/// A hairline between rows, starting where the text starts.
struct SettingsSeparator: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.separator).frame(height: 0.5).padding(.leading, 14)
    }
}

extension View {
    func settingsSwitch() -> some View { labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.phosphor) }
    func settingsMenu() -> some View { labelsHidden().pickerStyle(.menu).fixedSize() }
}
