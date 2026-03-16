import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: MinesweeperGame
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let cellSize = size / CGFloat(MinesweeperGame.cols)

            VStack(spacing: 12) {
                header

                board
                    .frame(width: cellSize * CGFloat(MinesweeperGame.cols),
                           height: cellSize * CGFloat(MinesweeperGame.rows))

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor.ignoresSafeArea())
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(game.minesLeft)")
                    .monospacedDigit()
                    .font(.system(size: 24, weight: .medium, design: .rounded))
            }

            Spacer()

            Button(action: { game.reset() }) {
                Image(systemName: game.isGameOver ? (game.isWin ? "face.smiling" : "face.dashed") : "face.smiling.inverse")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.monochrome)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeString(from: game.elapsedSeconds))
                    .monospacedDigit()
                    .font(.system(size: 24, weight: .medium, design: .rounded))
            }
        }
        .padding(.horizontal, 8)
    }

    private var board: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: MinesweeperGame.cols)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<MinesweeperGame.rows, id: \.self) { row in
                ForEach(0..<MinesweeperGame.cols, id: \.self) { col in
                    CellView(row: row, col: col)
                        .environmentObject(game)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.96)
    }

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct CellView: View {
    @EnvironmentObject private var game: MinesweeperGame
    @Environment(\.colorScheme) private var colorScheme

    let row: Int
    let col: Int

    var cell: Cell {
        game.cell(atRow: row, col: col)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            content
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .modifier(CellGestures(row: row, col: col))
        #if os(macOS)
        .contextMenu {
            Button {
                game.toggleFlag(row: row, col: col)
            } label: {
                Label(cell.state == .flagged ? "Unflag" : "Flag", systemImage: "flag.fill")
            }
        }
        #endif
    }

    private var backgroundColor: Color {
        switch cell.state {
        case .hidden, .flagged:
            return Color(white: colorScheme == .dark ? 0.28 : 0.88)
        case .revealed:
            if cell.isExploded {
                return .red.opacity(0.75)
            } else {
                return Color(white: colorScheme == .dark ? 0.20 : 0.96)
            }
        }
    }

    private var borderColor: Color {
        switch cell.state {
        case .hidden, .flagged:
            return Color.primary.opacity(0.18)
        case .revealed:
            return Color.primary.opacity(0.12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch cell.state {
        case .hidden:
            EmptyView()
        case .flagged:
            Image(systemName: "flag.fill")
                .foregroundColor(.red)
                .font(.system(size: 16, weight: .bold))
        case .revealed:
            if cell.isMine {
                Image(systemName: "circle.inset.filled")
                    .foregroundColor(.black)
                    .font(.system(size: 14, weight: .bold))
            } else if cell.adjacentMines > 0 {
                Text("\(cell.adjacentMines)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(numberColor(for: cell.adjacentMines))
            } else {
                EmptyView()
            }
        }
    }

    private func numberColor(for count: Int) -> Color {
        switch count {
        case 1: return .blue
        case 2: return .green
        case 3: return .red
        case 4: return .purple
        case 5: return .orange
        case 6: return .teal
        case 7: return .brown
        default: return .primary
        }
    }
}

private struct CellGestures: ViewModifier {
    @EnvironmentObject private var game: MinesweeperGame

    let row: Int
    let col: Int

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded { game.chord(row: row, col: col) }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in game.toggleFlag(row: row, col: col) }
            )
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { game.reveal(row: row, col: col) }
            )
        #else
        content
            .highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded { game.chord(row: row, col: col) }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.2)
                    .onEnded { _ in game.toggleFlag(row: row, col: col) }
            )
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { game.reveal(row: row, col: col) }
            )
        #endif
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let game = MinesweeperGame()
        ContentView()
            .environmentObject(game)
            .previewDevice("iPhone 15 Pro")
        #if os(macOS)
        ContentView()
            .environmentObject(game)
        #endif
    }
}
#endif

