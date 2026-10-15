import SwiftUI

public struct StepperField: View {
    @Binding public var value: Int
    public var range: ClosedRange<Int>
    public var unit: String

    public init(value: Binding<Int>, range: ClosedRange<Int> = 1...60, unit: String = "秒") {
        self._value = value
        self.range = range
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .frame(width: 44, alignment: .center)

                Divider()
                    .frame(height: 18)

                VStack(spacing: 0) {
                    Button(action: {
                        if value < range.upperBound {
                            value += 1
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(width: 16)

                    Button(action: {
                        if value > range.lowerBound {
                            value -= 1
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 18)
            }
            .frame(height: 24)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(unit)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
    }
}
