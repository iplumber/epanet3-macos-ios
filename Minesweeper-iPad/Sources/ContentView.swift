import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: MinesweeperGame

    var body: some View {
        VStack(spacing: 16) {
            statusBar
            board
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    game.reset()
                    Haptics.tap()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reset")
            }
        }
        .alert(isPresented: Binding(
            get: { game.isGameOver },
            set: { _ in }
        )) {
            Alert(
                title: Text(game.isWin ? "You Win!" : "Game Over"),
                message: Text(game.isWin ? "All safe cells revealed." : "You hit a mine."),
                dismissButton: .default(Text("New Game")) {
                    game.reset()
                }
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            statCard(title: "Mines", value: "\(game.minesLeft)")
            Spacer()
            Button {
                game.reset()
                Haptics.tap()
            } label: {
                Image(systemName: faceSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset game")
            Spacer()
            statCard(title: "Time", value: timeString(from: game.elapsedSeconds))
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var board: some View {
        GeometryReader { proxy in
            let available = min(proxy.size.width, proxy.size.height)
            let maxBoard: CGFloat = 520 // iPad mini 上更接近“桌面棋盘”的观感
            let boardSize = min(available, maxBoard)

            let maxCell: CGFloat = 56
            let minCell: CGFloat = 32
            let rawCell = boardSize / CGFloat(MinesweeperGame.cols)
            let cellSize = min(max(rawCell, minCell), maxCell)
            let finalBoard = cellSize * CGFloat(MinesweeperGame.cols)

            VStack {
                boardGrid(cellSize: cellSize)
                    .frame(width: finalBoard, height: finalBoard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 620) // iPad mini 竖屏足够；横屏也不会挤压状态栏
    }

    private func boardGrid(cellSize: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: 6), count: MinesweeperGame.cols)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<MinesweeperGame.rows, id: \.self) { row in
                ForEach(0..<MinesweeperGame.cols, id: \.self) { col in
                    CellView(row: row, col: col, cellSize: cellSize)
                        .environmentObject(game)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var faceSymbol: String {
        if !game.isGameOver { return "face.smiling" }
        return game.isWin ? "face.smiling.inverse" : "face.dashed"
    }

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct CellView: View {
    @EnvironmentObject private var game: MinesweeperGame

    let row: Int
    let col: Int
    let cellSize: CGFloat

    private var cell: Cell {
        game.cell(atRow: row, col: col)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            content

            CellGestureOverlay(
                onTap: { handleReveal() },
                onDoubleTap: { handleChord() },
                onLongPressOneFinger: { handleFlag() },
                onLongPressTwoFingers: { handleChord() }
            )
            .allowsHitTesting(!game.isGameOver)
        }
        .frame(width: cellSize, height: cellSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch cell.state {
        case .hidden:
            return "Hidden cell"
        case .flagged:
            return "Flagged cell"
        case .revealed:
            if cell.isMine { return "Mine" }
            if cell.adjacentMines == 0 { return "Empty" }
            return "\(cell.adjacentMines)"
        }
    }

    private var backgroundColor: Color {
        switch cell.state {
        case .hidden, .flagged:
            return Color(white: 0.86)
        case .revealed:
            if cell.isExploded {
                return .red.opacity(0.75)
            } else {
                return Color(white: 0.95)
            }
        }
    }

    private var borderColor: Color {
        switch cell.state {
        case .hidden, .flagged:
            return Color.black.opacity(0.14)
        case .revealed:
            return Color.black.opacity(0.10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch cell.state {
        case .hidden:
            EmptyView()
        case .flagged:
            Image(systemName: "flag.fill")
                .foregroundStyle(.red)
                .font(.system(size: max(18, cellSize * 0.42), weight: .bold))
        case .revealed:
            if cell.isMine {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(.black)
                    .font(.system(size: max(16, cellSize * 0.38), weight: .bold))
            } else if cell.adjacentMines > 0 {
                Text("\(cell.adjacentMines)")
                    .font(.system(size: max(18, cellSize * 0.42), weight: .bold, design: .rounded))
                    .foregroundStyle(numberColor(for: cell.adjacentMines))
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
        default: return .black
        }
    }

    private func handleReveal() {
        let result = game.reveal(row: row, col: col)
        switch result {
        case .revealed:
            Haptics.tap()
        case .exploded:
            Haptics.error()
        case .won:
            Haptics.success()
        case .ignored:
            break
        }
    }

    private func handleFlag() {
        let result = game.toggleFlag(row: row, col: col)
        switch result {
        case .flagged, .unflagged:
            Haptics.flag()
        case .ignored:
            break
        }
    }

    private func handleChord() {
        let result = game.chord(row: row, col: col)
        switch result {
        case .expanded:
            Haptics.tap()
        case .exploded:
            Haptics.error()
        case .won:
            Haptics.success()
        case .ignored:
            break
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MinesweeperGame())
            .previewDevice("iPad mini (6th generation)")
    }
}
#endif

