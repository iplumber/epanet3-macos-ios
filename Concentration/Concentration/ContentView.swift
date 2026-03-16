//
//  ContentView.swift
//  Concentration
//
//  Main game interface with adaptive layout
//

import SwiftUI

struct ContentView: View {
    @StateObject private var game = ConcentrationGame()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: Int {
        switch (game.pairCount, horizontalSizeClass) {
        case (.eight, .compact): return 4
        case (.eight, .regular): return 6
        case (.ten, .compact): return 5
        case (.ten, .regular): return 8
        case (.twelve, .compact): return 4
        case (.twelve, .regular): return 8
        case (_, nil): return 4
        }
    }

    private var cardMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 85 : 90
    }

    var body: some View {
        Group {
            if game.hasStarted {
                gameView
            } else {
                startScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.95))
    }

    private var startScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Concentration")
                .font(.largeTitle.bold())

            Text("记忆配对")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                Text("选择卡牌数量")
                    .font(.headline)
                Picker("卡牌数量", selection: $game.pairCount) {
                    ForEach(PairCount.allCases) { count in
                        Text(count.displayName).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
            }
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 32)

            Button(action: { game.startGame() }) {
                Text("开始游戏")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 48)

            Spacer()
        }
    }

    private var gameView: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = horizontalSizeClass == .regular ? 10 : 8
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)

            VStack(spacing: 16) {
                header

                if game.isGameComplete {
                    completionOverlay
                }

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: spacing) {
                        ForEach(Array(game.cards.enumerated()), id: \.element.id) { index, card in
                            CardView(card: card) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    game.chooseCard(at: index)
                                }
                            }
                            .frame(maxWidth: cardMaxWidth)
                        }
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 24) {
                    Button("重新选择数量") {
                        game.backToStart()
                    }
                    .font(.subheadline)

                    Button("新游戏") {
                        game.reset()
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已配对")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(game.matchedPairs) / \(game.totalPairs)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Button(action: { game.backToStart() }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回选择卡牌数量")

            Spacer()

            Button(action: { game.reset() }) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("步数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(game.moveCount)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
    }

    private var completionOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("完成！")
                .font(.title2.bold())
            Text("共 \(game.moveCount) 步")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("重新选择") {
                    game.backToStart()
                }
                .buttonStyle(.borderedProminent)

                Button("再来一局") {
                    game.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
    }
}

#Preview {
    ContentView()
        .previewDevice("iPhone 15")
}

#Preview("iPad") {
    ContentView()
        .previewDevice("iPad mini (6th generation)")
}
