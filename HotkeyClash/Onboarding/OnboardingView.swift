import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            if currentStep > 0 {
                OnboardingProgressView(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 20)
                    .padding(.horizontal, 40)
            }

            Group {
                switch currentStep {
                case 0:
                    WelcomeStep {
                        withAnimation { currentStep = 1 }
                    }
                case 1:
                    HowItWorksStep {
                        withAnimation { currentStep = 2 }
                    }
                case 2:
                    AccessibilityStep {
                        withAnimation { currentStep = 3 }
                    }
                case 3:
                    CompletionStep(onFinish: onComplete)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 560)
    }
}
