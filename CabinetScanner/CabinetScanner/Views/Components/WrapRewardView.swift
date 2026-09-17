import SwiftUI

/// The celebration shown the instant a box is wrapped. This is the whole point
/// of the wrap league — the packer sees the payoff at the moment of the action,
/// not buried in a reports screen they never open.
struct WrapRewardView: View {
    let reward: WrapReward

    @State private var appeared = false

    private var headline: String {
        if reward.isNewPersonalBest { return "New personal best" }
        if reward.isMilestone { return "\(reward.boxesToday) boxes today" }
        return "Box wrapped"
    }

    private var accent: Color {
        if reward.isNewPersonalBest { return .yellow }
        if reward.isMilestone { return .orange }
        return .green
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: reward.isNewPersonalBest ? "crown.fill" : "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(accent)
                .scaleEffect(appeared ? 1 : 0.4)

            Text("+\(reward.points)")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text(headline)
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 18) {
                rewardStat(value: "\(reward.boxesToday)", label: "today")
                Divider().frame(height: 26).overlay(.white.opacity(0.25))
                rewardStat(value: "\(reward.pointsToday)", label: "points")
            }

            if let remaining = reward.boxesToBeatBest {
                Text("\(remaining) more to beat your best day")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(accent.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }

    private func rewardStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
