import SwiftUI

struct CountdownView: View {
    let value: Int

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            Text("\(value)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(scale)
                .opacity(opacity)
                .onChange(of: value) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        scale = 1.2
                        opacity = 1.0
                    }
                    withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
                        scale = 0.8
                        opacity = 0.0
                    }
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scale = 1.2
                        opacity = 1.0
                    }
                    withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
                        scale = 0.8
                        opacity = 0.0
                    }
                }
        }
    }
}

struct RecordingIndicator: View {
    let duration: TimeInterval
    let onStop: () -> Void

    @State private var isBlinking = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(isBlinking ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isBlinking)

            Text(DurationFormatter.format(duration))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            Divider()
                .frame(height: 16)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .onAppear {
            isBlinking = true
        }
    }
}
