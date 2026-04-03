import SwiftUI

#if os(iOS)
struct WorkspaceFAB: View {
    let action: () -> Void
    @AppStorage("workspaceFABOnRight") private var isOnRight = true
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let buttonSize: CGFloat = 56
            let padding: CGFloat = 20
            let leftX = padding
            let rightX = screenWidth - buttonSize - padding
            let restingX = isOnRight ? rightX : leftX
            let clampedX = min(max(restingX + dragOffset, leftX), rightX)

            fabButton
                .position(
                    x: clampedX + buttonSize / 2,
                    y: geo.size.height - padding - buttonSize / 2
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            isDragging = false
                            let finalX = restingX + value.translation.width + buttonSize / 2
                            let midpoint = screenWidth / 2
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isOnRight = finalX > midpoint
                                dragOffset = 0
                            }
                        }
                )
        }
        .allowsHitTesting(true)
    }

    private var fabButton: some View {
        Button(action: action) {
            Image("MobiusStrip")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 85, height: 85)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                )
                .shadow(color: .white.opacity(0.2), radius: 10)
        }
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}
#else
struct WorkspaceFAB: View {
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: action) {
                    Image("MobiusStrip")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        )
                        .shadow(color: .white.opacity(0.15), radius: 8)
                }
                .buttonStyle(.plain)
                .padding(20)
            }
        }
    }
}
#endif
