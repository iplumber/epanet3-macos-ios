import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: MinesweeperGame

    var body: some View {
        ZStack {
            ClassicPalette.appBackground.ignoresSafeArea()

            VStack(spacing: 14) {
                headerPanel
                boardPanel
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
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
                message: Text(alertMessage),
                dismissButton: .default(Text("New Game")) {
                    game.reset()
                }
            )
        }
    }

    private var headerPanel: some View {
        HStack(spacing: 12) {
            DigitalCounter(value: game.minesLeft, digits: 3)
                .accessibilityLabel("Mines left \(game.minesLeft)")

            Spacer(minLength: 0)

            Button {
                game.reset()
                Haptics.tap()
            } label: {
                ClassicFace(isWin: game.isWin, isGameOver: game.isGameOver)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset game")

            Spacer(minLength: 0)

            DigitalCounter(value: game.elapsedSeconds, digits: 3)
                .accessibilityLabel("Time \(game.elapsedSeconds) seconds")
        }
        .padding(10)
        .background(ClassicPanel())
    }

    private var boardPanel: some View {
        GeometryReader { proxy in
            let available = min(proxy.size.width, proxy.size.height)
            let maxBoard: CGFloat = 520
            let boardSize = min(available, maxBoard)

            let maxCell: CGFloat = 54
            let minCell: CGFloat = 28
            let rawCell = boardSize / CGFloat(MinesweeperGame.cols)
            let cellSize = min(max(rawCell, minCell), maxCell)
            let finalBoard = cellSize * CGFloat(MinesweeperGame.cols)

            VStack {
                boardGrid(cellSize: cellSize, spacing: 1)
                    .frame(width: finalBoard, height: finalBoard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 600)
        .padding(10)
        .background(ClassicPanel())
    }

    private func boardGrid(cellSize: CGFloat, spacing: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: MinesweeperGame.cols)
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<(MinesweeperGame.rows * MinesweeperGame.cols), id: \.self) { index in
                let row = index / MinesweeperGame.cols
                let col = index % MinesweeperGame.cols
                CellView(row: row, col: col, cellSize: cellSize)
                    .environmentObject(game)
            }
        }
        .padding(10)
        .background(ClassicPalette.boardBackground)
        .overlay(ClassicBevel(isRaised: false, thickness: 3))
    }

    private var alertMessage: String {
        if game.isWin {
            let time = game.finalTimeSeconds ?? game.elapsedSeconds
            let timeStr = timeString(from: time)
            let rank = game.winRank ?? 0
            let rankStr = rank == 1 ? "Best time!" : "Rank #\(rank)"
            return "Time: \(timeStr)  •  \(rankStr)"
        } else {
            return "You hit a mine. All mines are shown."
        }
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
            Rectangle()
                .fill(backgroundColor)
                .overlay(bevel)

            content

            CellGestureOverlay(
                onTap: { handleReveal() },
                onDoubleTap: { handleChord() },
                onTwoFingerTap: { handleChord() },
                onLongPressOneFinger: { handleFlag() }
            )
            .allowsHitTesting(!game.isGameOver)
        }
        .frame(width: cellSize, height: cellSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var bevel: some View {
        switch cell.state {
        case .hidden, .flagged:
            ClassicBevel(isRaised: true, thickness: max(2, cellSize * 0.08))
        case .revealed:
            ClassicBevel(isRaised: false, thickness: max(1, cellSize * 0.04))
        }
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
            return ClassicPalette.cellHidden
        case .revealed:
            if cell.isExploded {
                return ClassicPalette.cellExploded
            } else {
                return ClassicPalette.cellRevealed
            }
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
                ZStack {
                    Circle()
                        .fill(.black)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 2)
                }
                .padding(cellSize * 0.22)
            } else if cell.adjacentMines > 0 {
                Text("\(cell.adjacentMines)")
                    .font(.system(size: max(18, cellSize * 0.48), weight: .heavy, design: .rounded))
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

private enum ClassicPalette {
    static let appBackground = Color(white: 0.78)
    static let boardBackground = Color(white: 0.70)
    static let cellHidden = Color(white: 0.78)
    static let cellRevealed = Color(white: 0.86)
    static let cellExploded = Color.red
}

private struct ClassicPanel: View {
    var body: some View {
        Rectangle()
            .fill(ClassicPalette.boardBackground)
            .overlay(ClassicBevel(isRaised: true, thickness: 4))
    }
}

private struct ClassicBevel: View {
    let isRaised: Bool
    let thickness: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let t = min(thickness, min(w, h) / 3)

            let light = Color.white.opacity(isRaised ? 0.95 : 0.55)
            let dark = Color.black.opacity(isRaised ? 0.35 : 0.15)

            ZStack {
                Rectangle().fill(.clear)
                    .overlay(alignment: .top) { Rectangle().fill(isRaised ? light : dark).frame(height: t) }
                    .overlay(alignment: .leading) { Rectangle().fill(isRaised ? light : dark).frame(width: t) }
                    .overlay(alignment: .bottom) { Rectangle().fill(isRaised ? dark : light).frame(height: t) }
                    .overlay(alignment: .trailing) { Rectangle().fill(isRaised ? dark : light).frame(width: t) }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct DigitalCounter: View {
    let value: Int
    let digits: Int

    var body: some View {
        let clamped = max(-999, min(999, value))
        Text(String(format: "%0*d", digits, clamped))
            .font(.system(size: 30, weight: .heavy, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color(red: 0.95, green: 0.12, blue: 0.12))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.92))
            .overlay(ClassicBevel(isRaised: false, thickness: 2))
    }
}

private struct ClassicFace: View {
    let isWin: Bool
    let isGameOver: Bool

    var body: some View {
        let symbol: String = {
            if !isGameOver { return "face.smiling" }
            return isWin ? "face.smiling.inverse" : "face.dashed"
        }()

        Image(systemName: symbol)
            .font(.system(size: 26, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: 54, height: 44)
            .background(ClassicPalette.cellHidden)
            .overlay(ClassicBevel(isRaised: true, thickness: 3))
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

