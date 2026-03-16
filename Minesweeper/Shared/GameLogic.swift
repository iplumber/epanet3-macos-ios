import Foundation

enum CellState {
    case hidden
    case revealed
    case flagged
}

struct Cell: Identifiable, Hashable {
    let id = UUID()
    let row: Int
    let col: Int
    var isMine: Bool = false
    var adjacentMines: Int = 0
    var state: CellState = .hidden
    var isExploded: Bool = false
}

final class MinesweeperGame: ObservableObject {
    static let rows = 9
    static let cols = 9
    static let mineCount = 10

    @Published private(set) var grid: [[Cell]] = []
    @Published private(set) var isGameOver: Bool = false
    @Published private(set) var isWin: Bool = false
    @Published private(set) var minesLeft: Int = mineCount
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var hasStarted: Bool = false

    private var timer: Timer?
    private var unrevealedSafeCells: Int = rows * cols - mineCount

    init() {
        reset()
    }

    func reset() {
        grid = (0..<Self.rows).map { r in
            (0..<Self.cols).map { c in
                Cell(row: r, col: c)
            }
        }
        isGameOver = false
        isWin = false
        minesLeft = Self.mineCount
        elapsedSeconds = 0
        hasStarted = false
        unrevealedSafeCells = Self.rows * Self.cols - Self.mineCount
        stopTimer()
    }

    private func startTimerIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.isGameOver {
                self.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func placeMines(excluding firstRow: Int, firstCol: Int) {
        var positions: [(Int, Int)] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if r == firstRow && c == firstCol { continue }
                positions.append((r, c))
            }
        }
        positions.shuffle()
        let minePositions = positions.prefix(Self.mineCount)

        for (r, c) in minePositions {
            grid[r][c].isMine = true
        }

        // compute adjacent mine counts
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                guard !grid[r][c].isMine else { continue }
                grid[r][c].adjacentMines = neighbors(ofRow: r, col: c)
                    .filter { grid[$0.0][$0.1].isMine }
                    .count
            }
        }
    }

    private func neighbors(ofRow row: Int, col: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let nr = row + dr
                let nc = col + dc
                if nr >= 0 && nr < Self.rows && nc >= 0 && nc < Self.cols {
                    result.append((nr, nc))
                }
            }
        }
        return result
    }

    func cell(atRow row: Int, col: Int) -> Cell {
        grid[row][col]
    }

    func reveal(row: Int, col: Int) {
        guard !isGameOver else { return }
        guard row >= 0 && row < Self.rows && col >= 0 && col < Self.cols else { return }
        var cell = grid[row][col]
        guard cell.state == .hidden else { return }

        startTimerIfNeeded()

        if !hasAnyMinePlaced() {
            placeMines(excluding: row, firstCol: col)
            // recompute cell after mines placed
            cell = grid[row][col]
        }

        if cell.isMine {
            // game over
            grid[row][col].isExploded = true
            revealAllMines()
            isGameOver = true
            isWin = false
            stopTimer()
            return
        }

        floodReveal(fromRow: row, col: col)
        checkWinCondition()
    }

    private func floodReveal(fromRow row: Int, col: Int) {
        var stack: [(Int, Int)] = [(row, col)]
        while let (r, c) = stack.popLast() {
            var cell = grid[r][c]
            if cell.state != .hidden || cell.isMine { continue }
            cell.state = .revealed
            grid[r][c] = cell
            unrevealedSafeCells -= 1
            if cell.adjacentMines == 0 {
                for (nr, nc) in neighbors(ofRow: r, col: c) {
                    if grid[nr][nc].state == .hidden && !grid[nr][nc].isMine {
                        stack.append((nr, nc))
                    }
                }
            }
        }
    }

    func toggleFlag(row: Int, col: Int) {
        guard !isGameOver else { return }
        guard row >= 0 && row < Self.rows && col >= 0 && col < Self.cols else { return }
        var cell = grid[row][col]
        guard cell.state != .revealed else { return }

        switch cell.state {
        case .hidden:
            cell.state = .flagged
            minesLeft -= 1
        case .flagged:
            cell.state = .hidden
            minesLeft += 1
        case .revealed:
            break
        }
        grid[row][col] = cell
    }

    func chord(row: Int, col: Int) {
        guard !isGameOver else { return }
        guard row >= 0 && row < Self.rows && col >= 0 && col < Self.cols else { return }
        let cell = grid[row][col]
        guard cell.state == .revealed else { return }
        guard cell.adjacentMines > 0 else { return }

        let neighborPositions = neighbors(ofRow: row, col: col)
        let flaggedCount = neighborPositions
            .filter { grid[$0.0][$0.1].state == .flagged }
            .count

        if flaggedCount == cell.adjacentMines {
            for (nr, nc) in neighborPositions {
                let neighbor = grid[nr][nc]
                if neighbor.state == .hidden {
                    if neighbor.isMine {
                        grid[nr][nc].isExploded = true
                        revealAllMines()
                        isGameOver = true
                        isWin = false
                        stopTimer()
                        return
                    } else {
                        floodReveal(fromRow: nr, col: nc)
                    }
                }
            }
            checkWinCondition()
        }
    }

    private func revealAllMines() {
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if grid[r][c].isMine {
                    if grid[r][c].state == .hidden {
                        grid[r][c].state = .revealed
                    }
                }
            }
        }
    }

    private func hasAnyMinePlaced() -> Bool {
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if grid[r][c].isMine {
                    return true
                }
            }
        }
        return false
    }

    private func checkWinCondition() {
        if unrevealedSafeCells == 0 {
            isGameOver = true
            isWin = true
            stopTimer()
        }
    }
}

