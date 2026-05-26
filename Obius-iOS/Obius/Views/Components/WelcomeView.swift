import SwiftUI

/// First-launch onboarding tour that explains what Obius is and shows
/// inline visual examples of the core concepts (intents, loops, echoes).
/// Gated by `@AppStorage("hasSeenWelcome")` — also reachable from Settings.
struct WelcomeView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pageCount = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    intentsPage.tag(1)
                    loopsPage.tag(2)
                    echoesPage.tag(3)
                    finalPage.tag(4)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        withAnimation { isPresented = false }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                finish()
            } label: {
                Text(currentPage == pageCount - 1 ? "" : "Skip")
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .opacity(currentPage == pageCount - 1 ? 0 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 22) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    Capsule()
                        .fill(idx == currentPage ? Color.white : Color.white.opacity(0.18))
                        .frame(width: idx == currentPage ? 18 : 6, height: 6)
                        .animation(.spring(duration: 0.3), value: currentPage)
                }
            }

            Button {
                if currentPage < pageCount - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(currentPage == pageCount - 1 ? "Get Started" : "Continue")
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 36)
        .padding(.top, 12)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()

            Image("ObiusLogoClean")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)

            VStack(spacing: 8) {
                Text("Obius")
                    .font(.custom("LexendExa-SemiBold", size: 38, relativeTo: .largeTitle))
                    .foregroundStyle(.white)

                Text("Notes that evolve.")
                    .font(.custom("Inter-Regular", size: 17))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text("Most notes apps are graveyards — you write something, scroll past it, never see it again. Obius is built for thinking that keeps moving: sections change shape, ideas link to each other, and what you wrote yesterday folds into what you're building today.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 36)
                .padding(.top, 8)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Intents

    private var intentsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                pageHeader(
                    eyebrow: "Sections",
                    title: "Color your thinking",
                    subtitle: "Every section carries an intent. The color tells you what kind of thinking lives there — at a glance, no reading required."
                )

                VStack(spacing: 8) {
                    demoSection(intent: .idea, text: "What if notes could rearrange themselves over time?")
                    demoSection(intent: .question, text: "Is this actually different from what Notion already does?")
                    demoSection(intent: .evidence, text: "Möbius strip — one continuous surface, no beginning or end.")
                    demoSection(intent: .issue, text: "Users dropping off after the second screen.")
                    demoSection(intent: .task, text: "Submit to App Store.")
                }
                .padding(.horizontal, 22)

                footnote("Tap a section to switch its intent. Reorder, collapse, or nest them as your thinking changes.")
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Page 3: Loops

    private var loopsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                pageHeader(
                    eyebrow: "Loops",
                    title: "Write once, reuse everywhere",
                    subtitle: "A Loop is a reusable block prefixed with @. Drop it into any note. Edit it anywhere — every copy updates instantly."
                )

                VStack(spacing: 10) {
                    loopDemoCard(
                        noteTitle: "Kitchen",
                        body: "Things to grab this week:",
                        handle: "@weekly_groceries"
                    )

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 24, height: 1)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text("Same Loop")
                            .font(.custom("Inter-Medium", size: 10))
                            .tracking(0.4)
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 24, height: 1)
                    }
                    .foregroundStyle(.white.opacity(0.35))

                    loopDemoCard(
                        noteTitle: "Sunday meal prep",
                        body: "Pulling shopping list straight from the kitchen note:",
                        handle: "@weekly_groceries"
                    )
                }
                .padding(.horizontal, 22)

                footnote("Edit the grocery list from either note — both stay in sync. Loops become your reusable building blocks.")
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Page 4: Echoes

    private var echoesPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                pageHeader(
                    eyebrow: "Echoes",
                    title: "Notes that find you back",
                    subtitle: "Attach a time-based reminder to any Loop. When the moment matters, the note resurfaces with its full context — not a one-line ping."
                )

                VStack(spacing: 10) {
                    echoDemoCard(
                        handle: "@morning_routine",
                        schedule: "Every weekday · 7:30 AM",
                        intent: .idea
                    )

                    echoDemoCard(
                        handle: "@weekly_review",
                        schedule: "Sundays · 6:00 PM",
                        intent: .evidence
                    )

                    echoDemoCard(
                        handle: "@quarterly_planning",
                        schedule: "First Monday each quarter",
                        intent: .task
                    )
                }
                .padding(.horizontal, 22)

                footnote("Unlike calendar pings, Echoes carry the full note with them — so when you're reminded, you pick up where you left off.")
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Page 5: Get Started

    private var finalPage: some View {
        VStack(spacing: 30) {
            Spacer()

            Image("ObiusLogoClean")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            VStack(spacing: 10) {
                Text("Start thinking in loops")
                    .font(.custom("LexendExa-SemiBold", size: 26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Your first note is one tap away.")
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 16) {
                quickTip(icon: "plus.circle.fill", color: .white, text: "Tap + to start a new note")
                quickTip(icon: "paintpalette.fill", color: .blue, text: "Tap a section to change its intent")
                quickTip(icon: "at", color: .purple, text: "Type @ to create or reuse a Loop")
                quickTip(icon: "bell.fill", color: .orange, text: "Long-press a Loop to set an Echo")
                quickTip(icon: "icloud.fill", color: .cyan, text: "Sign in anytime to sync across devices")
            }
            .padding(.horizontal, 36)
            .padding(.top, 6)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Building Blocks

    private func pageHeader(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.custom("Inter-SemiBold", size: 10))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.35))

            Text(title)
                .font(.custom("LexendExa-SemiBold", size: 24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(subtitle)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.custom("Inter-Regular", size: 12))
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 36)
            .padding(.top, 4)
    }

    private func demoSection(intent: IntentType, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(intent.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: intent.icon)
                        .font(.system(size: 9))
                    Text(intent.label.uppercased())
                        .font(.custom("Inter-SemiBold", size: 9))
                        .tracking(0.8)
                }
                .foregroundStyle(intent.color)

                Text(text)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(intent.color.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(intent.color.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func loopDemoCard(noteTitle: String, body: String, handle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text(noteTitle.uppercased())
                    .font(.custom("Inter-SemiBold", size: 10))
                    .tracking(0.8)
            }
            .foregroundStyle(.white.opacity(0.4))

            Text(body)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                Text(handle)
                    .font(.custom("Inter-Medium", size: 13))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.13))
            .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(white: 0.13), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func echoDemoCard(handle: String, schedule: String, intent: IntentType) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(intent.color.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: "bell.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(intent.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(handle)
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                Text(schedule)
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(white: 0.13), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func quickTip(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 22)

            Text(text)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.78))

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    WelcomeView(isPresented: .constant(true))
}
