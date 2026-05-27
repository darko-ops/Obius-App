import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Seeds the "Personal" project + sample pages for brand-new sign-ups so the
/// app isn't empty on first launch.
///
/// Triggering: `AuthManager.signUp` marks the global signup flag before
/// supabase emits `.signedIn`. `AppState.initialize()` converts the global
/// flag to a per-user pending flag once it knows the new user's id, then
/// runs this seeder against the per-user database.
///
/// All non-loop body text is written to `note.body` (head) or
/// `note.interstitialContent` (between sections). Loops are fold-style
/// portal sections. We never create `.line` sections — they render with
/// section context menus and drag handles, which isn't what we want for
/// non-interactive demo prose.
@MainActor
struct OnboardingSeeder {
    private static let pendingFlagPrefix = "obius.pendingOnboardingSeed."
    /// Global flag set by `AuthManager.signUp` BEFORE `supabase.signUp` runs,
    /// because the auth-state observer can fire `switchUser → initialize`
    /// during the SDK's internal awaits — before `AuthManager.signUp` ever
    /// reaches the line that marks the per-user flag. `AppState.initialize`
    /// converts this back to a per-user flag once `currentUserId` is set.
    static let globalSignupFlag = "obius.signupNeedsSeed"

    let moduleRepository: ModuleRepository
    let noteRepository: NoteRepository
    let sectionRepository: SectionRepository
    let handleRepository: HandleRepository
    let echoRepository: EchoRepository

    // MARK: - Pending flag

    static func markPending(userId: String) {
        UserDefaults.standard.set(true, forKey: pendingFlagPrefix + userId)
    }

    static func isPending(userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: pendingFlagPrefix + userId)
    }

    static func clearPending(userId: String) {
        UserDefaults.standard.removeObject(forKey: pendingFlagPrefix + userId)
    }

    static func markSignupInProgress() {
        UserDefaults.standard.set(true, forKey: globalSignupFlag)
    }

    static func clearSignupInProgress() {
        UserDefaults.standard.removeObject(forKey: globalSignupFlag)
    }

    static func isSignupInProgress() -> Bool {
        UserDefaults.standard.bool(forKey: globalSignupFlag)
    }

    // MARK: - Seed

    /// Returns `true` only if Personal exists and all three demo pages are
    /// present at the end of the run, so the caller can defer clearing the
    /// pending flag if anything failed and retry on the next initialize.
    func seed() async -> Bool {
        print("[OnboardingSeeder] Starting seed…")
        let project: Module
        do {
            project = try await getOrCreatePersonalProject()
            print("[OnboardingSeeder] Personal project id=\(project.id.prefix(8))")
        } catch {
            print("[OnboardingSeeder] FAILED to get/create Personal project: \(error)")
            return false
        }

        // Notes are observed ordered by updatedAt.desc, so the LAST note
        // touched ends up at the top of the list. Seed bottom-to-top:
        // Quotes → Tim Ferriss → Welcome.
        let quotesOK = await runStep("Quotes") { try await seedQuotes(in: project.id) }
        let timOK = await runStep("Tim Ferriss") { try await seedTimFerriss(in: project.id) }
        let welcomeOK = await runStep("Welcome") { try await seedWelcome(in: project.id) }

        // Remove the empty "Artifacts" module that the v34 schema migration
        // inserts on fresh per-user databases (also the SyncEngine fallback's
        // creation). Personal is the real first project now; Artifacts would
        // just be empty clutter.
        await removeAutoArtifactsIfPresent()

        let success = quotesOK && timOK && welcomeOK
        print("[OnboardingSeeder] Done. Personal id=\(project.id.prefix(8)), success=\(success) (quotes=\(quotesOK), tim=\(timOK), welcome=\(welcomeOK))")
        return success
    }

    private func runStep(_ label: String, _ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            print("[OnboardingSeeder] ✓ \(label) page seeded")
            return true
        } catch {
            print("[OnboardingSeeder] ✗ \(label) page failed: \(error)")
            return false
        }
    }

    /// Returns the existing "Personal" module if one exists, otherwise creates it.
    /// This makes the seeder idempotent — a retry after a partial failure won't
    /// duplicate the project.
    private func getOrCreatePersonalProject() async throws -> Module {
        if let existing = try await moduleRepository.getModuleByName("Personal") {
            return existing
        }
        return try await moduleRepository.createModule(
            name: "Personal", icon: "folder", storageType: .cloud
        )
    }

    private func removeAutoArtifactsIfPresent() async {
        do {
            if let artifacts = try await moduleRepository.getModuleByName("Artifacts") {
                _ = try await moduleRepository.deleteModule(id: artifacts.id)
            }
        } catch {
            print("[OnboardingSeeder] Could not remove auto-Artifacts: \(error)")
        }
    }

    // MARK: - Welcome page

    private func seedWelcome(in moduleId: String) async throws {
        let note = try await noteRepository.createNote(
            title: "Welcome to Obius", intent: .idea, moduleId: moduleId
        )

        // Founder letter with Obius / Nodes / Echoes / Loops bolded.
        let (plain, rich) = Self.welcomeBodyText()
        try await noteRepository.updateNoteBody(note.id, body: plain, richText: rich)

        // Below the letter: a collapsed portal section linked to the SAME
        // Romans12_21 handle used on the Quotes page (seeded earlier so the
        // handle already exists). Multiple portal sections can point at the
        // same handle — editing in one place updates everywhere.
        guard let romans = try await handleRepository.getHandleByName("Romans12_21") else { return }
        let portal = try await sectionRepository.createSection(
            noteId: note.id, sectionType: .fold, afterSectionId: nil
        )
        try await sectionRepository.linkSectionToHandle(sectionId: portal.id, handleId: romans.id)
        try await sectionRepository.setIntent(portal.id, intent: .idea)
        try await sectionRepository.toggleCollapse(portal.id) // start collapsed
    }

    /// Builds the founder letter body with Obius / Nodes / Echoes / Loops
    /// rendered in bold. Returns both plain and RTF base64 — the editor falls
    /// back to plain if rich-text decoding fails on another platform.
    private static func welcomeBodyText() -> (plain: String, rich: String?) {
        // (text, bold)
        let segments: [(String, Bool)] = [
            ("Being someone who struggles with a constant scatter-brain and constantly starting new projects, I built ", false),
            ("Obius", true),
            (" to help me organize my life in one place.\n\n", false),
            ("Obius", true),
            (" is a simple, intuitive way to organize thoughts and research — or a visual project management tool for tracking workflows and decisions. Whatever your use case, the intelligence running in the background is designed to help you make connections between projects.\n\nDefine your context and chat naturally, or build new documents in the page editor.\n\nInside, you'll find ", false),
            ("Nodes", true),
            (" — stylistically simple yet powerful blocks of words, images, or audio. You can turn these ", false),
            ("Nodes", true),
            (" into ", false),
            ("Echoes", true),
            (", which act as reminders with a function, or ", false),
            ("Loops", true),
            (", which can be referenced globally to maximize the functionality of all your work.\n\n— Demetri, Founder", false),
        ]

        let attr = NSMutableAttributedString()
        let regular = RichTextHelper.bodyAttributes()
        let bold = boldBodyAttributes()
        for (text, isBold) in segments {
            attr.append(NSAttributedString(string: text, attributes: isBold ? bold : regular))
        }
        return (attr.string, RichTextHelper.serialize(attr))
    }

    private static func boldBodyAttributes() -> [NSAttributedString.Key: Any] {
        #if os(iOS)
        return [
            .font: UIFont.systemFont(ofSize: RichTextHelper.bodySize, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        #else
        return [
            .font: NSFont.systemFont(ofSize: RichTextHelper.bodySize, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        #endif
    }

    // MARK: - Quotes page

    private func seedQuotes(in moduleId: String) async throws {
        let note = try await noteRepository.createNote(
            title: "Quotes", intent: .idea, moduleId: moduleId
        )

        try await noteRepository.updateNoteBody(
            note.id,
            body: "Here are some quotes…"
        )

        let quotes: [(handle: String, intent: IntentType, text: String)] = [
            ("Romans12_21", .idea,     "Do not be overcome by evil, but overcome evil with good."),
            ("LeoDaVinci",  .question, "Simplicity is the ultimate sophistication."),
            ("Godin",       .evidence, "There is no shortage of remarkable ideas, what's missing is the will to execute them."),
            ("Socrates",    .task,     "Strong minds discuss ideas, average minds discuss events, weak minds discuss people."),
        ]

        var previousId: String? = nil
        for quote in quotes {
            previousId = try await addLoopSection(
                noteId: note.id,
                after: previousId,
                handleName: quote.handle,
                intent: quote.intent,
                handleContent: quote.text
            ).id
        }
    }

    // MARK: - Tim Ferriss page

    private func seedTimFerriss(in moduleId: String) async throws {
        let note = try await noteRepository.createNote(
            title: "The Tim Ferriss Lifestyle Guide", intent: .idea, moduleId: moduleId
        )

        // Intro paragraphs + Big "Daily practices" heading all live in
        // note.body so they render as normal prose with no drag handle or
        // section context menu.
        let (bodyPlain, bodyRich) = Self.timFerrissBodyText()
        try await noteRepository.updateNoteBody(note.id, body: bodyPlain, richText: bodyRich)

        var previousId: String? = nil

        previousId = try await addFoldWithHeading(
            noteId: note.id, after: previousId,
            heading: "Fear-Setting",
            body: """
            The exercise Ferriss recommends above all others — he calls it more valuable than goal-setting. When stuck on a decision or paralyzed by worry, take a page and make three columns:

            1. Define — What's the worst that could realistically happen? List every fear in concrete detail.
            2. Prevent — What could you do to reduce the chance of each?
            3. Repair — If the worst happened, how would you recover? Who could you ask for help?

            Most fears shrink the n your thoughts, you separate yourself from them.
            """
        ).id

        previousId = try await addFoldWithHeading(
            noteId: note.id, after: previousId,
            heading: "The 5-Minute Journal",
            body: "Two minutes in the morning, two at night. Ferriss has called it his highest-ROI habit."
        ).id

        previousId = try await addFoldWithHeading(
            noteId: note.id, after: previousId,
            heading: "Morning",
            body: """
            • 3 things I'm grateful for
            • 3 things that would make today great
            • A daily affirmation
            """
        ).id

        // @AMJournal loop + echo (daily at 8:30 AM local time)
        previousId = try await addLoopSection(
            noteId: note.id, after: previousId,
            handleName: "AMJournal", intent: .idea,
            handleContent: """
            Grateful:
            1.
            2.
            3.

            Great:
            1.
            2.
            3.

            Affirmation:
            1.
            """
        ).id
        try await scheduleDailyEcho(forHandleNamed: "AMJournal", hour: 8, minute: 30)

        previousId = try await addFoldWithHeading(
            noteId: note.id, after: previousId,
            heading: "Evening",
            body: """
            • 3 amazing things that happened today
            • What could I have done to make today better?
            """
        ).id

        // @PMJournal loop + echo (daily at 8:30 PM local time)
        previousId = try await addLoopSection(
            noteId: note.id, after: previousId,
            handleName: "PMJournal", intent: .question,
            handleContent: """
            Amazing Things:
            1.
            2.
            3.

            What Could Be Better?
            1.
            """
        ).id
        try await scheduleDailyEcho(forHandleNamed: "PMJournal", hour: 20, minute: 30)

        previousId = try await addFoldWithHeading(
            noteId: note.id, after: previousId,
            heading: "The 80/20 Audit",
            body: """
            Every few months, sit down and ask:
            • Which 20% of activities give me 80% of my results, joy, or income?
            • Which 20% of people, tasks, or commitments cause 80% of my stress?

            Do more of the first list. Cut the second. Repeat.
            """
        ).id

        _ = try await addFoldWithHeading(
            noteId: note.id, after: previousId,
            heading: "A better question for hard problems",
            body: "When stuck, swap \"How do I do this?\" for \"What would this look like if it were easy?\" The honest answer usually points at a better path than the one you were forcing."
        )
    }

    /// Builds the Tim Ferriss page body: two intro paragraphs in body type,
    /// an explicit empty line, then a "Daily practices" heading at the same
    /// size as the editor toolbar's "Big text" / Title style.
    private static func timFerrissBodyText() -> (plain: String, rich: String?) {
        // Two `\n\n` between the paragraphs gives the usual paragraph break;
        // the extra "\n" before "Daily practices" inserts an empty row.
        let intro = """
        Tim Ferriss is an author, investor, and podcaster best known for The 4-Hour Workweek and Tools of Titans. He's spent two decades interviewing world-class performers and stress-testing their habits on himself. He treats his own life as an experiment — and the notebook is where he runs it.

        Here are a few of his most useful practices, plus quotes worth keeping.


        """

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: intro, attributes: RichTextHelper.bodyAttributes()))
        attr.append(NSAttributedString(string: "Daily practices", attributes: bigTitleAttributes()))

        return (attr.string, RichTextHelper.serialize(attr))
    }

    /// Same attributes the toolbar's "Big text" / Title button applies: h1
    /// size, bold weight. Keep this in sync with `applyTitle()` in
    /// SectionView's rich-text helper.
    private static func bigTitleAttributes() -> [NSAttributedString.Key: Any] {
        #if os(iOS)
        return [
            .font: UIFont.systemFont(ofSize: RichTextHelper.h1Size, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        #else
        return [
            .font: NSFont.systemFont(ofSize: RichTextHelper.h1Size, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        #endif
    }

    // MARK: - Builders

    @discardableResult
    private func addFold(noteId: String, after: String?, title: String, content: String) async throws -> Section {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            content: content,
            sectionType: .fold,
            afterSectionId: after
        )
        try await sectionRepository.setTitle(section.id, title: title)
        return section
    }

    /// Creates a fold section whose first line is a bold heading inside the
    /// content itself (no `section.title`). This keeps the heading editable
    /// and visible in the collapsed preview row.
    @discardableResult
    private func addFoldWithHeading(noteId: String, after: String?, heading: String, body: String) async throws -> Section {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            sectionType: .fold,
            afterSectionId: after
        )
        let plain = "\(heading)\n\n\(body)"
        let rich = Self.foldHeadingRichContent(heading: heading, body: body)
        try await sectionRepository.updateContent(section.id, content: plain, richText: rich)
        return section
    }

    /// Bold first line + regular body, both at body size — "normal text"
    /// per the design ask, but with the heading visually distinct so the
    /// collapsed preview still reads like a heading.
    private static func foldHeadingRichContent(heading: String, body: String) -> String? {
        let attr = NSMutableAttributedString()
        let bold = boldBodyAttributes()
        let regular = RichTextHelper.bodyAttributes()
        attr.append(NSAttributedString(string: heading + "\n\n", attributes: bold))
        attr.append(NSAttributedString(string: body, attributes: regular))
        return RichTextHelper.serialize(attr)
    }

    /// Creates a Loop (Handle) and a portal section that displays its content.
    private func addLoopSection(
        noteId: String,
        after: String?,
        handleName: String,
        intent: IntentType,
        handleContent: String
    ) async throws -> Section {
        let handle = try await handleRepository.createHandle(
            name: handleName, content: handleContent, intent: intent
        )
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            sectionType: .fold,
            afterSectionId: after
        )
        try await sectionRepository.linkSectionToHandle(sectionId: section.id, handleId: handle.id)
        try await sectionRepository.setIntent(section.id, intent: intent)
        return section
    }

    /// Sets up a daily recurring echo for the named handle at the given local time.
    /// `Echo.computedNextFireDate` walks forward from `fireDate` by the interval
    /// until it lands in the future, so passing today's 8:30 works whether or
    /// not the time has already passed.
    private func scheduleDailyEcho(forHandleNamed name: String, hour: Int, minute: Int) async throws {
        guard let handle = try await handleRepository.getHandleByName(name) else { return }
        let cal = Calendar.current
        let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        _ = try await echoRepository.createEcho(
            handleId: handle.id,
            isRecurring: true,
            intervals: [EchoInterval(value: 1, unit: .days)],
            fireDate: Int64(fire.timeIntervalSince1970 * 1000)
        )
    }
}
