//
//  CardView.swift
//  Concentration
//
//  Single card view with flip animation
//

import SwiftUI

struct CardView: View {
    let card: Card
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if card.isFaceUp || card.isMatched {
                cardFront
            } else {
                cardBack
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .onTapGesture {
            if !card.isMatched && !card.isFaceUp {
                onTap()
            }
        }
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.4, green: 0.6, blue: 0.9),
                             Color(red: 0.2, green: 0.4, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "apple.logo")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
            )
    }

    private var cardFront: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(white: 0.98))
            .overlay(
                Image(systemName: card.animalType.symbolName)
                    .font(.system(size: 32))
                    .foregroundStyle(card.isMatched ? .green : .primary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        card.isMatched ? Color.green.opacity(0.6) : Color.primary.opacity(0.15),
                        lineWidth: 2
                    )
            )
            .opacity(card.isMatched ? 0.7 : 1)
    }
}

#Preview {
    VStack(spacing: 20) {
        CardView(
            card: Card(animalType: .cat, id: UUID()),
            onTap: {}
        )
        .frame(width: 80)

        CardView(
            card: Card(animalType: .dog, id: UUID()),
            onTap: {}
        )
        .frame(width: 80)
    }
    .padding()
}
