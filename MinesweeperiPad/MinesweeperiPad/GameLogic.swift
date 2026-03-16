import Foundation
import Combine

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
    /// 通关时的排名（1 = 第一），仅胜利时有值
    @Published private(set) var winRank: Int?
    /// 通关时间（秒），仅胜利时有值
    @Published private(set) var finalTimeSeconds: Int?

    private var timer: Timer?
    private static let bestTimesKey = "MinesweeperBestTimes"
    private static let bestTimesCount = 10
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
        winRank = nil
        finalTimeSeconds = nil
        unrevealedSafeCells = Self.rows * Self.cols - Self.mineCount
        stopTimer()
    }

    func cell(atRow row: Int, col: Int) -> Cell {
        grid[row][col]
    }

    func reveal(row: Int, col: Int) -> RevealResult {
        guard !isGameOver else { return .ignored }
        guard row >= 0 && row < Self.rows && col >= 0 && col < Self.cols else { return .ignored }
        var cell = grid[row][col]
        guard cell.state == .hidden else { return .ignored }

        startTimerIfNeeded()

        if !hasAnyMinePlaced() {
            placeMines(excluding: row, firstCol: col)
            cell = grid[row][col]
        }

        if cell.isMine {
            grid[row][col].isExploded = true
            revealAllMines()
            isGameOver = true
            isWin = false
            stopTimer()
            return .exploded
        }

        floodReveal(fromRow: row, col: col)
        if checkWinCondition() {
            return .won
        }
        return .revealed
    }

    func toggleFlag(row: Int, col: Int) -> FlagResult {
        guard !isGameOver else { return .ignored }
        guard row >= 0 && row < Self.rows && col >= 0 && col < Self.cols else { return .ignored }
        var cell = grid[row][col]
        guard cell.state != .revealed else { return .ignored }

        switch cell.state {
        case .hidden:
            cell.state = .flagged
            minesLeft -= 1
            grid[row][col] = cell
            return .flagged
        case .flagged:
            cell.state = .hidden
            minesLeft += 1
            grid[row][col] = cell
            return .unflagged
        case .revealed:
            return .ignored
        }
    }

    func chord(row: Int, col: Int) -> ChordResult {
        guard !isGameOver else { return .ignored }
        guard row >= 0 && row < Self.rows && col >= 0 && col < Self.cols else { return .ignored }
        let cell = grid[row][col]
        guard cell.state == .revealed else { return .ignored }
        guard cell.adjacentMines > 0 else { return .ignored }

        let neighborPositions = neighbors(ofRow: row, col: col)
        let flaggedCount = neighborPositions
            .filter { grid[$0.0][$0.1].state == .flagged }
            .count

        guard flaggedCount == cell.adjacentMines else { return .ignored }

        for (nr, nc) in neighborPositions {
            let neighbor = grid[nr][nc]
            if neighbor.state == .hidden {
                if neighbor.isMine {
                    grid[nr][nc].isExploded = true
                    revealAllMines()
                    isGameOver = true
                    isWin = false
                    stopTimer()
                    return .exploded
                } else {
                    floodReveal(fromRow: nr, col: nc)
                }
            }
        }

        if checkWinCondition() {
            return .won
        }
        return .expanded
    }
}

extension MinesweeperGame {
    enum RevealResult { case revealed, exploded, won, ignored }
    enum FlagResult { case flagged, unflagged, ignored }
    enum ChordResult { case expanded, exploded, won, ignored }
}

private extension MinesweeperGame {
    func startTimerIfNeeded() {
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

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func placeMines(excluding firstRow: Int, firstCol: Int) {
        var positions: [(Int, Int)] = []
        positions.reserveCapacity(Self.rows * Self.cols - 1)

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

        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                guard !grid[r][c].isMine else { continue }
                grid[r][c].adjacentMines = neighbors(ofRow: r, col: c)
                    .filter { grid[$0.0][$0.1].isMine }
                    .count
            }
        }
    }

    func neighbors(ofRow row: Int, col: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        result.reserveCapacity(8)
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

    func floodReveal(fromRow row: Int, col: Int) {
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

    /// 失败时：显示所有未翻开的雷
    func revealAllMines() {
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if grid[r][c].isMine, grid[r][c].state == .hidden {
                    grid[r][c].state = .revealed
                }
            }
        }
    }

    /// 胜利时：把所有雷标成旗
    func flagAllMines() {
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if grid[r][c].isMine, grid[r][c].state == .hidden {
                    grid[r][c].state = .flagged
                }
            }
        }
        minesLeft = 0
    }

    /// 记录本次通关时间并计算排名
    func recordWinAndRank() {
        let t = elapsedSeconds
        finalTimeSeconds = t
        var list = Self.loadBestTimes()
        list.append(t)
        list.sort()
        list = Array(list.prefix(Self.bestTimesCount))
        Self.saveBestTimes(list)
        winRank = (list.firstIndex(of: t) ?? 0) + 1
    }

    static func loadBestTimes() -> [Int] {
        (UserDefaults.standard.array(forKey: bestTimesKey) as? [Int]) ?? []
    }

    private static func saveBestTimes(_ list: [Int]) {
        UserDefaults.standard.set(list, forKey: bestTimesKey)
    }

    func hasAnyMinePlaced() -> Bool {
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if grid[r][c].isMine { return true }
            }
        }
        return false
    }

    @discardableResult
    func checkWinCondition() -> Bool {
        if unrevealedSafeCells == 0 {
            isGameOver = true
            isWin = true
            flagAllMines()
            recordWinAndRank()
            stopTimer()
            return true
        }
        return false
    }
}

