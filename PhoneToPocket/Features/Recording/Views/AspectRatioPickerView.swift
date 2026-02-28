import SwiftUI

struct AspectRatioPickerView: View {
    @Binding var selectedRatio: AspectRatio
    var onChanged: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            categoryMenu(category: .landscape, options: AspectRatio.ratios(for: .landscape))
            categoryMenu(category: .portrait, options: AspectRatio.ratios(for: .portrait))

            Button {
                selectedRatio = .fullGate
                onChanged()
            } label: {
                pillLabel(AspectRatioCategory.fullGate,
                          isSelected: selectedRatio == .fullGate)
            }
        }
    }

    @ViewBuilder
    private func categoryMenu(category: AspectRatioCategory, options: [AspectRatio]) -> some View {
        let isSelected = selectedRatio.category == category
        Menu {
            ForEach(options) { ratio in
                Button {
                    selectedRatio = ratio
                    onChanged()
                } label: {
                    HStack {
                        Text(ratio.rawValue)
                        if ratio == selectedRatio { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            pillLabel(category, isSelected: isSelected)
        }
    }

    @ViewBuilder
    private func pillLabel(_ cat: AspectRatioCategory, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: cat.icon).font(.caption2)
            Text(cat.rawValue).font(.caption.bold())
        }
        .foregroundStyle(isSelected ? .black : .white.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Capsule())
    }
}
