//
//  GameLogic.swift
//  Concentration
//
//  Memory matching game logic
//

import SwiftUI

// MARK: - Animal Type (SF Symbols, extensible for custom images)
enum AnimalType: String, CaseIterable, Identifiable {
    case cat
    case dog
    case fish
    case bird
    case hare
    case tortoise
    case lizard
    case ant
    case ladybug
    case leaf
    case butterfly
    case pawprint

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .fish: return "fish.fill"
        case .bird: return "bird.fill"
        case .hare: return "hare.fill"
        case .tortoise: return "tortoise.fill"
        case .lizard: return "lizard.fill"
        case .ant: return "ant.fill"
        case .ladybug: return "ladybug.fill"
        case .leaf: return "leaf.fill"
        case .butterfly: return "butterfly.fill"
        case .pawprint: return "pawprint.fill"
        }
    }

    static func animals(for pairCount: Int) -> [AnimalType] {
        Array(AnimalType.allCases.prefix(pairCount))
    }
}

// MARK: - Card Model
struct Card: Identifiable, Equatable {
    let id: UUID
    let animalType: AnimalType
    var isFaceUp: Bool
    var isMatched: Bool

    init(animalType: AnimalType, id: UUID = UUID()) {
        self.id = id
        self.animalType = animalType
        self.isFaceUp = false
        self.isMatched = false
    }
}

// MARK: - Game Options
enum PairCount: Int, CaseIterable, Identifiable {
    case eight = 8
    case ten = 10
    case twelve = 12

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue) 对"
    }
}

// MARK: - Game Logic
@MainActor
final class ConcentrationGame: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published private(set) var matchedPairs: Int = 0
    @Published private(set) var moveCount: Int = 0
    @Published private(set) var isGameComplete: Bool = false
    @Published private(set) var hasStarted: Bool = false

    @Published var pairCount: PairCount = .eight {
        didSet {
            if oldValue != pairCount && hasStarted {
                reset()
            }
        }
    }

    private var faceUpCardIndices: [Int] = []
    private var flipBackTask: Task<Void, Never>?

    var totalPairs: Int { pairCount.rawValue }

    init() {}

    func startGame() {
        hasStarted = true
        reset()
    }

    func backToStart() {
        hasStarted = false
        cards = []
        matchedPairs = 0
        moveCount = 0
        isGameComplete = false
        faceUpCardIndices = []
        flipBackTask?.cancel()
        flipBackTask = nil
    }

    func reset() {
        flipBackTask?.cancel()
        flipBackTask = nil
        faceUpCardIndices = []

        guard hasStarted else { return }

        let animals = AnimalType.animals(for: pairCount.rawValue)
        var newCards: [Card] = []
        for animal in animals {
            newCards.append(Card(animalType: animal))
            newCards.append(Card(animalType: animal))
        }
        cards = newCards.shuffled()
        matchedPairs = 0
        moveCount = 0
        isGameComplete = false
    }

    func chooseCard(at index: Int) {
        guard index < cards.count else { return }
        guard !cards[index].isMatched else { return }
        guard !cards[index].isFaceUp else { return }

        flipBackTask?.cancel()
        objectWillChange.send()

        if faceUpCardIndices.count == 2 {
            for i in faceUpCardIndices {
                var c = cards[i]
                c.isFaceUp = false
                cards[i] = c
            }
            faceUpCardIndices = []
        }

        var tapped = cards[index]
        tapped.isFaceUp = true
        cards[index] = tapped
        faceUpCardIndices.append(index)

        if faceUpCardIndices.count == 2 {
            moveCount += 1
            let first = cards[faceUpCardIndices[0]]
            let second = cards[faceUpCardIndices[1]]

            if first.animalType == second.animalType {
                var c0 = cards[faceUpCardIndices[0]]
                var c1 = cards[faceUpCardIndices[1]]
                c0.isMatched = true
                c1.isMatched = true
                cards[faceUpCardIndices[0]] = c0
                cards[faceUpCardIndices[1]] = c1
                matchedPairs += 1
                faceUpCardIndices = []

                if matchedPairs == totalPairs {
                    isGameComplete = true
                }
            } else {
                let indices = faceUpCardIndices
                flipBackTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    for i in indices {
                        var c = cards[i]
                        c.isFaceUp = false
                        cards[i] = c
                    }
                    faceUpCardIndices = []
                }
            }
        }
    }

    func cardIndex(for card: Card) -> Int? {
        cards.firstIndex { $0.id == card.id }
    }
}
