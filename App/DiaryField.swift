import SwiftUI

/// Multiline field that works inside a ScrollView. TextEditor in a ScrollView
/// drops taps, hides text, and can fail to keep the binding.
struct DiaryField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(8...24)
            .padding(12)
            .frame(minHeight: 180, alignment: .topLeading)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}
