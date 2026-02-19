# Obius Positioning Strategy

---

## 1. What Makes Obius Valuable

Obius is not another notes app. It is a **structured thinking engine** that treats ideas as first-class objects rather than flat text in a file.

### Core Value Drivers

**A. Local-first data sovereignty**
Every note lives on-device in SQLite. The cloud is optional, not required. In an era where Notion goes down and Evernote sunsets features, Obius guarantees your thinking is never held hostage by a server. This is not a feature — it is an architectural commitment.

**B. Sections as the unit of thought**
Most notes apps give you a blank page. Obius gives you collapsible, reorderable, nestable **sections** — each with its own content type (text, checklist, code, quote, image, audio), intent tag (idea, question, task, evidence), and color. This is closer to how the brain organizes information: not as monolithic documents, but as discrete, movable building blocks.

**C. Handle Loop — reusable idea portals**
This is the feature no competitor has in this form. A Handle is a named, global content block. Any section can link to a Handle, and editing one updates all linked instances instantly. This turns notes from isolated silos into an interconnected knowledge graph without the complexity of tools like Roam or Obsidian.

**D. Immutable Commits — snapshots you can share**
Obius borrows from version control: any note or section can be committed as a SHA-256 hashed, immutable snapshot. You can share a commit link knowing the recipient sees exactly what you intended — it cannot be silently edited after the fact. This is a trust primitive that no other notes app offers.

**E. AI as a lens, not a crutch**
AI generates titles, summaries, and powers semantic search — but it never writes your notes for you. The AI is an organizational accelerator, not a content generator. This is a deliberate philosophical choice that respects the user's thinking process.

**F. Privacy by architecture**
Local-first storage, biometric locks on sections, encrypted sync. Privacy is not a policy — it is a structural constraint baked into the data model.

---

## 2. Use Cases by Industry

### Legal
- **Structured case briefs**: Sections tagged as Evidence, Question, Task map directly to legal reasoning workflows.
- **Immutable commits for documentation**: Timestamped, hashed snapshots of notes serve as verifiable records of when an idea or finding was documented.
- **Client-safe sharing**: Share a commit link to opposing counsel or a client — they see exactly what you intended, nothing more.
- **Privileged information**: Biometric-locked sections keep sensitive case notes behind Face ID even if someone picks up the device.

### Medicine & Clinical Research
- **Patient encounter notes**: Sections for subjective, objective, assessment, plan (SOAP format) using intent tags and collapsible structure.
- **Research hypothesis tracking**: Handle Loops let a core hypothesis propagate across multiple study notes — update the hypothesis once, it updates everywhere.
- **Offline-first for field work**: Clinicians in rural areas, field researchers in remote locations — Obius works without connectivity.
- **Audit trail via commits**: Immutable snapshots document the evolution of clinical reasoning over time.

### Education & Academia
- **Lecture note structuring**: Students organize notes as collapsible sections by topic, then tag questions for later review.
- **Thesis/dissertation management**: Handle Loops let a central thesis statement propagate across chapter notes. Modify it once, every reference updates.
- **Study group sharing**: Share immutable commit snapshots of class notes — recipients cannot alter the original.
- **Research synthesis**: Intent-tagged sections (Idea, Evidence, Question) let researchers visually filter and reorganize source material.

### Software Engineering
- **Architecture decision records**: Each decision as a section with intent tags (Evidence for data, Question for open items, Task for follow-ups).
- **Incident post-mortems**: Timestamped commit snapshots create an immutable timeline of findings.
- **Code snippet management**: Code-type sections with syntax awareness, organized by project via nested sections.
- **Offline documentation**: Works on planes, in server rooms, in any environment without reliable connectivity.

### Journalism & Investigative Work
- **Source management**: Biometric-locked sections protect source identities. Immutable commits prove when information was documented.
- **Story structuring**: Sections as movable building blocks for assembling narratives from scattered facts.
- **Evidence chain**: Handle Loops connect a key fact across multiple story drafts — if the fact changes, every reference updates.
- **Sharing drafts safely**: Commit-based sharing means editors see exactly what was sent, preventing version confusion.

### Creative Work (Writing, Music, Design)
- **Idea capture with structure**: Random ideas as sections that can be reordered, nested, and tagged without losing the original context.
- **Project bible**: Handle Loops as canonical character descriptions, world-building rules, or brand guidelines that propagate across all related notes.
- **Version history**: Commits as creative checkpoints — snapshot a draft before a major revision.
- **Offline-first for focus**: No internet required means no distractions.

### Consulting & Strategy
- **Client engagement notes**: Structured sections for observations, recommendations, open questions — collapsible for executive summaries.
- **Framework application**: Template sections for repeating frameworks (SWOT, Porter's Five Forces, Jobs-to-be-Done) applied per client.
- **Deliverable snapshots**: Commit-share a strategic finding to a client as an immutable, timestamped artifact.
- **Cross-engagement patterns**: Handle Loops let consultants maintain reusable insight blocks that appear across multiple client notes.

---

## 3. Stress Test — What Could Kill Obius

### Existential Threats

**A. Apple Notes is "good enough"**
Apple Notes ships free on every iPhone. It has folders, tags, scanning, collaboration, and improving search. For 80% of users, it does 80% of what they need. Obius must convince users that the 20% gap (sections, Handles, commits, intent tags) is worth switching for. If Apple adds collapsible blocks or structured sections, Obius loses its most visible differentiator overnight.

*Mitigation*: The value is not in any single feature — it is in the architectural philosophy (local-first + structured + immutable). Apple will never build Handle Loops or commit-based sharing because those are opinionated design choices that conflict with Apple's simplicity mandate.

**B. Notion/Obsidian already own the "structured thinking" category**
Notion owns "blocks as units" for teams. Obsidian owns "local-first knowledge graph" for individuals. Obius sits between them and risks being perceived as a weaker version of both.

*Mitigation*: Notion is cloud-first and team-oriented — it requires internet and is designed for collaboration, not personal thinking. Obsidian is desktop-first and requires Markdown literacy — it is a power tool for technical users. Obius is **mobile-native, local-first, and designed for non-technical thinkers who want structure without complexity**. This is a real gap.

**C. The "second brain" fatigue**
The market is saturated with productivity tools promising to be your "second brain." Users are exhausted. Many have tried Roam, Notion, Obsidian, Logseq, and returned to Apple Notes or pen and paper. Obius enters a market with deep skepticism about new entrants.

*Mitigation*: Position Obius NOT as a second brain or PKM tool. Position it as a **notes app that thinks the way you do** — structured, private, always available. Avoid the PKM vocabulary entirely.

**D. Monetization uncertainty**
Local-first architecture means the server is optional. If the core product works offline, what do users pay for? Sync? AI? Sharing? Each of these has free alternatives. The business model must justify ongoing payment without compromising the local-first promise.

*Mitigation*: Charge for the app itself (one-time purchase or modest subscription for sync + AI). The paid value is the *engineering quality* of the sync engine, the AI features, and the sharing infrastructure — not access to your own data.

**E. Single-platform risk (iOS only)**
An iOS-only app locks out Android users and limits the addressable market by roughly half. It also makes Obius vulnerable to Apple's App Store policy changes, API deprecations, or review rejections.

*Mitigation*: macOS support is already in the codebase. A web client or Android app is the obvious next step, but the local-first SQLite architecture makes cross-platform non-trivial. This is a real engineering constraint that must be planned for early.

**F. Handle Loops are hard to explain**
The most unique feature — Handle Loops — is also the hardest to explain. "Reusable content portals" sounds abstract. If users don't discover or understand Handles, they miss the primary differentiator and see Obius as just another notes app.

*Mitigation*: Onboarding must demonstrate Handle Loops with a concrete, visceral example in the first 60 seconds. Show, don't tell. A handle called "My Address" that appears in five notes and updates everywhere when you move apartments — that is instantly understandable.

**G. No moat beyond execution**
The features are replicable. Any well-funded team could build sections, handles, and commits. The moat must come from execution speed, design taste, community, and the compounding value of a user's data being structured in Obius's format.

*Mitigation*: Ship fast. Build community early. Create export formats that are open (prevent lock-in perception) but structured enough that the Obius experience is hard to replicate by importing into a competitor.

### Things That Will NOT Kill It
- "AI features are table stakes" — True, but Obius's AI is deliberately restrained. This is a feature, not a bug.
- "No collaboration" — Obius is for personal thinking. Collaboration is sharing, not co-editing. This is a positioning choice.
- "Too niche" — Niche is survivable. The danger is being generic.

---

## 4. Minimum Viable Market Segment

### Target: Independent knowledge workers on iOS who think in outlines

**Specifically:**
- Solo lawyers, freelance consultants, independent researchers, PhD students, senior engineers, technical writers
- Age 25-45
- iOS-primary (iPhone + Mac)
- Currently using Apple Notes or Bear and feeling the limits
- Have tried Notion or Obsidian but found them too heavy, too team-oriented, or too technical
- Value privacy and offline access (not for paranoid reasons, but for practical reliability)
- Produce structured written output as part of their work (briefs, reports, proposals, papers)

**Why this segment first:**
1. They already pay for productivity tools (low price sensitivity for quality)
2. They feel the pain of unstructured notes daily (high frequency of use)
3. They can articulate the value to peers (organic word-of-mouth in professional communities)
4. They are reachable via targeted channels (legal tech blogs, academic Twitter/Mastodon, indie hacker communities, developer podcasts)
5. They are small enough to serve well but large enough to sustain a business

**Segment size estimate:** ~2-5M globally (iOS-using independent professionals who actively seek better note-taking tools). Capturing 0.1% = 2,000-5,000 paying users — enough to validate and fund the next phase.

**Entry wedge:** Target one sub-community first. Recommendation: **solo lawyers and legal professionals**. They have the highest pain (structured case notes, evidence documentation, immutable records, privacy requirements) and the highest willingness to pay for tools that serve their workflow.

---

## 5. One-Sentence Killer Thesis

> **Obius is the notes app where every idea is a building block — structured, private, permanent, and yours.**

### Why this works:
- **"every idea is a building block"** — captures sections, Handles, and the composability of the system
- **"structured"** — differentiates from flat notes apps
- **"private"** — local-first, biometric locks
- **"permanent"** — immutable commits, offline availability
- **"yours"** — data sovereignty, no cloud dependency

### Alternatives considered:
- *"Your thinking, structured and sovereign."* — Too abstract.
- *"Notes that think the way you do."* — Closer, but doesn't convey the structural innovation.
- *"The offline-first notes app for structured thinkers."* — Too feature-listy.

---

## 6. Four Moonshots

### Moonshot 1: The Portable Proof Layer

**Vision:** Obius becomes the standard format for verifiable, timestamped idea documentation.

**The problem:** In patent disputes, academic priority claims, legal proceedings, and journalism, proving *when* you documented something matters enormously. Today this requires expensive notarization, blockchain timestamps, or institutional record-keeping.

**The path:** Obius already has SHA-256 hashed, immutable commits. Extend this with:
- Optional cryptographic timestamping (RFC 3161 or similar) anchored to a public time authority
- Export commits as self-verifying `.obx` files that anyone can validate without Obius installed
- Court-admissible documentation format (work with legal tech partners on evidentiary standards)

**Impact:** Obius becomes the tool of choice for anyone who needs to prove "I had this idea / documented this finding at this time." Patent-pending inventors, investigative journalists, clinical researchers, whistleblowers. This is not a notes app feature — it is a **trust infrastructure** built on top of notes.

**Significance:** No consumer notes app offers cryptographic proof of documentation. This is a category-defining capability.

---

### Moonshot 2: The Living Knowledge Mesh

**Vision:** Handle Loops evolve into a cross-user, cross-device knowledge network where canonical facts propagate in real time across trusted circles.

**The problem:** Teams and communities maintain shared knowledge (definitions, standards, procedures, reference data) that lives in wikis nobody updates and documents nobody reads. When the canonical fact changes, downstream references go stale silently.

**The path:**
- Allow Handle subscriptions: User A publishes a Handle ("Q3 Revenue Target: $4.2M"). User B subscribes. When A updates the Handle, B's notes update automatically.
- Build trust layers: subscribe only from verified sources, with change notifications and diff history.
- Start with small circles (a law firm's precedent definitions, a research lab's protocol parameters, a startup's OKRs) and expand.

**Impact:** Obius becomes the **single source of truth protocol** for small, high-trust groups. Not a collaboration tool (no co-editing), but a **propagation tool** — canonical facts flow downstream without manual copying.

**Significance:** This solves a problem that Notion, Confluence, and Google Docs all fail at: keeping downstream references in sync with upstream truth. Handle Loops are the primitive. The mesh is the moonshot.

---

### Moonshot 3: The Structured Thinking API

**Vision:** Obius becomes a platform where structured thought — not raw text — is the data format that other tools consume and produce.

**The problem:** Every productivity tool stores notes as unstructured text or proprietary blocks. When you want to move ideas between tools (notes to project management, notes to writing software, notes to presentations), you copy-paste and lose all structure, intent, and relationships.

**The path:**
- Define an open Obius Structured Note Format (sections with types, intents, handles, hierarchy)
- Build import/export adapters: Obius sections become Jira tickets, slide outlines, document sections, database rows
- Expose a local API so other apps on the device can read/write structured notes (Shortcuts, Automator, third-party integrations)
- Let AI agents operate on structured notes: "Turn all my Question-tagged sections into a research agenda" or "Convert this note's Task sections into calendar events"

**Impact:** Obius becomes the **structured thinking interchange format** — the place where ideas get organized before they flow into execution tools. Not a replacement for project management or writing software, but the thinking layer that feeds them.

**Significance:** Today, the gap between "thinking about what to do" and "doing it in a tool" is bridged by manual copy-paste. Obius can automate that bridge because its data is already structured with intent.

---

### Moonshot 4: The Cognitive Audit Trail

**Vision:** Obius becomes the tool that lets individuals and organizations trace how decisions were actually made — from initial question through evidence gathering to conclusion.

**The problem:** In regulated industries (healthcare, finance, legal, government), decisions must be documented and auditable. But the *process* of arriving at a decision — the questions asked, evidence weighed, alternatives considered — is almost never captured. It lives in people's heads and dies with their memory.

**The path:**
- Leverage intent-tagged sections (Question, Evidence, Idea, Task) as a natural decision-trail format
- Build a "Decision View" that renders a note's sections as a visual reasoning chain: Question → Evidence gathered → Ideas considered → Decision made → Tasks assigned
- Add optional structured metadata: confidence levels on Evidence sections, priority rankings on Idea sections, status tracking on Task sections
- Generate compliance-ready exports: "Here is the documented reasoning chain for Decision X, with timestamped commits at each stage"

**Impact:** Obius becomes the **decision documentation standard** for professionals who need to show their work. Doctors documenting clinical reasoning. Portfolio managers documenting investment theses. Engineers documenting architecture decisions. Lawyers documenting case strategy.

**Significance:** No tool captures the *process* of thinking — only the output. Obius already has the primitives (intent tags, sections, commits). The moonshot is making the thinking process itself visible, auditable, and trustworthy.

---

---

## 7. Auto-Commits: The Feature That Makes Provenance Passive

### The Idea

Today, Obius commits are manual — the user decides when to snapshot. Auto-commits create immutable snapshots on a recurring cadence (every hour, every day, on app close) so the user gets a timestamped reasoning trail *without thinking about it*.

### Why This Is Strategically Important

This is the bridge feature between "notes app" and "decision documentation" that doesn't require a product pivot or new data models.

**Without auto-commits:** The provenance value proposition requires user discipline. Users must remember to commit. Most won't. The audit trail has gaps. The decision documentation angle remains theoretical.

**With auto-commits:** Every note automatically accumulates a timestamped, hashed history of how it evolved. The user writes naturally. Obius silently builds the proof layer underneath. When a user later needs to show "here's how my thinking developed" — for a client, a court, a review board, or themselves — the trail already exists.

This is the difference between a feature users *could* use and a value they *passively receive*.

### Architectural Feasibility: Confirmed (High Confidence)

After reviewing the codebase, auto-commits are highly feasible because the required primitives already exist:

**Already built:**
- `CommitModule.createCommit()` — full async commit pipeline (snapshot, hash, write to Cold Store, index in Hot Store)
- `EchoInterval` + `EchoIntervalUnit` — recurring interval logic (minutes through months) with next-fire-date calculation
- `EchoManager` — scheduling pattern using `UNUserNotificationCenter` and scene-phase lifecycle hooks
- `ColdStore` — content-addressable .obx file storage with SHA-256 naming
- App lifecycle hooks in `ObiusApp.swift` for foreground activation checks

**Needs building:**
- `AutoCommitManager` class (modeled after `EchoManager`)
- Per-note or global auto-commit configuration (DB migration for settings)
- Change detection (skip commit if nothing changed since last commit)
- Retention policy (prevent unbounded commit accumulation)
- UI toggle in note settings

**Estimated effort:** ~5-7 days of development.

### Recommended Design Decisions

1. **Per-note opt-in, with a global default.** Let users enable auto-commits on important notes. Offer a global "auto-commit all notes" setting for power users. Default: off.
2. **Cadence options:** Every hour, every day, on note close, on app background. Daily is the sensible default for most users.
3. **Change detection:** Only commit if the note's content hash differs from the last commit. No duplicate snapshots.
4. **Auto-commit naming:** System-generated names like "Auto — Feb 19, 2026, 3:00 PM" to distinguish from intentional commits.
5. **Retention:** Keep all auto-commits for 90 days. After 90 days, keep only one per week. After 1 year, keep only one per month. User can override.
6. **Visual distinction:** Auto-commits appear slightly muted in the commit history, distinguishable from intentional commits but still fully functional.

### Strategic Value

Auto-commits turn Obius from "a notes app that *can* document your reasoning" into "a notes app that *does* document your reasoning." That's the difference between a feature and a value proposition. This single feature makes the "document how you think" positioning real rather than aspirational.

---

## 8. Go-to-Market Plan

### Vision Statement

Obius launches as a premium notes app for professionals who need structured, private, provable documentation of their thinking — positioned with the language of decision documentation but built as an elegant, simple notes experience.

**The principle:** Ship notes. Market provenance. Let users discover the decision documentation value through use. Don't over-engineer for a market that hasn't been validated.

---

### Phase 0: Pre-Launch Foundation (Weeks 1-6)

**Objective:** Build the audience before the product is available.

**0.1 — Landing Page (Week 1)**

Launch a single-page site at obius.io with:
- Headline: "Document how you think."
- Subhead: "Obius is the notes app where every idea is a building block — structured, private, permanent, and yours."
- A 30-second demo video showing: create a note, add sections with intent tags, collapse/reorder, create a commit, share the immutable link.
- Email waitlist with a single field.
- No pricing. No feature list. Just the video and the waitlist.

The landing page does one job: filter for people who feel the pain of unstructured notes. Everyone else bounces. That's fine.

**0.2 — Content Seeding (Weeks 1-6)**

Write 4-6 short pieces (blog posts, threads, or short-form video) targeting the beachhead audience:

| # | Title | Channel | Audience |
|---|-------|---------|----------|
| 1 | "Why I stopped using Apple Notes for case research" | Legal tech blogs, LinkedIn | Solo lawyers |
| 2 | "The problem with notes apps: they don't know what a thought is" | Personal blog, Hacker News | Technical professionals |
| 3 | "Structured notes vs. flat notes: why your ideas deserve more than a blank page" | Medium, Twitter/X | Knowledge workers broadly |
| 4 | "What if your notes could prove when you had an idea?" | LinkedIn, legal tech | Lawyers, researchers, IP professionals |
| 5 | "I built a commit system for notes — here's why" | Hacker News, Indie Hackers | Developers, technical founders |
| 6 | "Local-first notes: why your ideas shouldn't need WiFi" | Privacy-focused communities, Reddit | Privacy-conscious professionals |

**No paid ads at this stage.** The goal is organic signal from people who resonate with the framing. If nobody responds to "document how you think," that's important data — cheaper to learn from blog silence than from App Store silence.

**0.3 — Closed Beta (Weeks 3-6)**

Invite 20-50 waitlist signups to TestFlight. Prioritize:
- People who mentioned legal, research, or consulting in their signup
- People who replied to the content pieces
- People who asked "when can I try it"

Beta goals:
- Does the onboarding make sense without explanation?
- Do users discover intent tags and commits organically, or do they ignore them?
- What do users actually use Obius for? (This is the most important question. The answer may surprise you.)
- Collect 5-10 quotes for the App Store listing.

---

### Phase 1: Public Launch (Weeks 7-10)

**Objective:** Get Obius into the App Store and achieve first 500 downloads.

**1.1 — App Store Listing**

- **App Name:** Obius — Structured Notes
- **Subtitle:** Document how you think.
- **Category:** Productivity
- **Keywords:** notes, structured, local-first, offline, sections, organize, ai, sync, privacy, commit, professional, writing
- **Description lead:** "Obius is a local-first notes app where your ideas live as structured, searchable sections. Every thought has a place. Every change is permanent. Your data is yours."
- **Screenshots:** Focus on 4 moments:
  1. A note with collapsible sections and intent tags (the "aha" moment)
  2. A Handle Loop updating across notes (the differentiator)
  3. A commit being created and shared (the trust primitive)
  4. Offline editing with the local-first badge (the reliability promise)

**1.2 — Pricing**

**Freemium with a clear upgrade path:**

| Tier | Price | What You Get |
|------|-------|--------------|
| **Free** | $0 | Unlimited notes and sections. Local storage. Intent tags. Collapsible sections. Manual commits (up to 10 per note). |
| **Obius Pro** | $3.99/month or $34.99/year | Unlimited commits. Auto-commits. AI titles and summaries. Semantic search. Cross-device sync. Share links with comments. Biometric section locks. |

**Why this pricing:**
- Free tier is genuinely useful — not a crippled demo. Users must experience the section-based structure to understand the value.
- Pro is priced below Notion ($8-10/mo) and Bear ($2.99/mo) but above commodity. $35/year is impulse-buy territory for a professional.
- Auto-commits behind Pro creates a natural upgrade trigger: "You've been using Obius for a week. Want your notes to automatically build a history? Upgrade to Pro."
- No "team plan" at launch. That's a Phase 3 conversation after validating individual demand.

**1.3 — Launch Week Channels**

| Channel | Action | Expected Reach |
|---------|--------|----------------|
| **Product Hunt** | Launch with a maker story about local-first architecture and the commit system | 2,000-10,000 views |
| **Hacker News** | "Show HN: I built a notes app with git-style commits" — lead with the technical architecture | 5,000-20,000 views |
| **Indie Hackers** | Build-in-public post about the journey, architecture decisions, and early metrics | 1,000-5,000 views |
| **Reddit** | r/productivity, r/ObsidianMD (as an alternative for mobile-first users), r/apple | 1,000-5,000 per post |
| **Waitlist email** | "Obius is live" email to all waitlist subscribers | 100% of waitlist |
| **Legal tech newsletters** | Pitch to Above the Law, Lawyerist, Legal Tech Monitor | Varies, high-quality leads |

**1.4 — Launch Week Success Metrics**

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| Downloads (Week 1) | 500+ | Proves basic market interest |
| Free-to-Pro conversion | 5-8% | Validates willingness to pay |
| Day 7 retention | 30%+ | Proves the product is sticky, not just novel |
| Commit creation rate | 20%+ of active users create at least 1 commit | Validates the core differentiator resonates |
| Intent tag usage | 15%+ of sections have non-default intent tags | Validates structured thinking is used, not ignored |

---

### Phase 2: Beachhead Penetration (Months 2-6)

**Objective:** Own the solo-lawyer niche. Achieve 2,000 paying users.

**2.1 — Legal-Specific Content**

After launch data confirms (or refutes) the legal beachhead hypothesis, invest in targeted content:

- "How to structure case briefs in Obius" (tutorial)
- "Using immutable commits for client documentation" (use case walkthrough)
- "Obius for deposition prep: evidence sections and biometric locks" (workflow guide)
- Partner with 2-3 legal tech bloggers or YouTubers for reviews

**2.2 — Feature Priorities Based on User Signal**

| If users do this... | Build this next... |
|---------------------|-------------------|
| Create lots of commits manually | Auto-commits (already designed, ship it) |
| Ignore intent tags | Simplify to fewer options, add AI auto-tagging |
| Use Handle Loops heavily | Cross-note Handle search, Handle dashboard |
| Request collaboration | Comment threads on shared commits (already built) |
| Request Android/web | Start web client scoping (Phase 3) |
| Churn after 2 weeks | Investigate onboarding, simplify first-run experience |

**2.3 — Community Building**

- Launch a Discord or dedicated community space (not Slack — too transient).
- Invite beta users and power users.
- Use the community for feature prioritization, bug reports, and case studies.
- Identify 5-10 "champion users" who can write testimonials and refer peers.

**2.4 — Month 6 Success Metrics**

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| Paying users | 2,000+ | Sustainable at ~$70K ARR |
| Monthly churn | <5% | Proves long-term stickiness |
| NPS | 40+ | Measures genuine enthusiasm vs. passive usage |
| Organic referrals | 20%+ of new users from word-of-mouth | Validates the product sells itself |
| Commits per active user per month | 5+ | Proves the core value proposition is being used |

---

### Phase 3: Expansion (Months 7-18)

**Objective:** Expand beyond the legal beachhead. Reach 10,000 paying users.

**3.1 — Second Audience: Academic Researchers**

If the legal beachhead succeeds, researchers are the natural second audience:
- Similar pain (structured evidence, hypothesis tracking, audit trails)
- Similar price tolerance (academic tools are routinely $50-100/year)
- Different channels (academic Twitter, ResearchGate, university tech blogs)

**3.2 — Platform Expansion**

Priority order based on user demand signal:
1. **macOS app** (already in codebase, polish and ship)
2. **Web client** (read-only initially — view shared commits, browse notes)
3. **Android** (only if demand signal is strong enough to justify the engineering investment)

**3.3 — Moonshot Feature Sequencing**

Based on our earlier analysis, the sequencing that maximizes likelihood of success:

| Order | Moonshot | When | Trigger |
|-------|----------|------|---------|
| 1st | **Structured Thinking API** (Shortcuts, export adapters) | Month 8-10 | Power users requesting integrations |
| 2nd | **Cognitive Audit Trail** (Decision View, compliance exports) | Month 10-14 | Legal/medical users requesting formatted reasoning chains |
| 3rd | **Portable Proof Layer** (cryptographic timestamps) | Month 14-18 | Demand from IP professionals, researchers, or journalists |
| 4th | **Living Knowledge Mesh** (cross-user Handles) | Month 18+ | Only after sufficient user base for network effects |

**3.4 — Pricing Evolution**

At 10,000+ users, introduce:
- **Obius Pro+** at $7.99/month or $69.99/year: adds Structured Thinking API access, advanced export formats, compliance-ready PDF exports with cryptographic timestamps
- Keep the core Pro tier unchanged — never take features away from existing customers

**3.5 — Month 18 Success Metrics**

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| Paying users | 10,000+ | ~$350K-500K ARR, sustainable indie business |
| Platform coverage | iOS + macOS + web (read) | Reduces single-platform risk |
| Audiences served | 3+ professional verticals | Reduces single-market risk |
| Revenue per user (annual) | $35-50 | Validates premium positioning |

---

### Phase 4: Category Definition (Year 2+)

**Objective:** Transition from "premium notes app" to "professional decision documentation."

This is where the ChatGPT vision becomes relevant — but only after you have:
- 10,000+ paying users who validate the product
- Revenue to fund the engineering investment
- User data showing how professionals actually use commits, intent tags, and audit trails
- Organic evidence that users describe Obius in decision-documentation terms

**At this point, and not before:**
- Rebrand positioning from "structured notes" to "document how you think" as the primary identity
- Introduce the Decision View as a first-class feature
- Pursue legal tech partnerships for court-admissible documentation
- Explore enterprise pilots with small law firms, research labs, or consulting practices
- Consider the AI decision intake layer (Obius as the human review surface for AI-generated decisions)

The category emerges from validated user behavior, not from pre-launch positioning.

---

### GTM Anti-Patterns to Avoid

| Don't Do This | Do This Instead |
|---------------|-----------------|
| Launch with "decision ledger" positioning | Launch with "structured notes" and let the decision use case emerge |
| Build Decision Objects before v1.0 ships | Ship sections + commits, observe how users build decision trails naturally |
| Target enterprises before you have individual users | Win individuals first, let them bring Obius into their organizations |
| Spend on paid ads before organic channels are validated | Content + community + launches first, paid acquisition only after CAC/LTV is understood |
| Build Android before macOS | macOS is already in the codebase and serves your iOS beachhead users who also have Macs |
| Price at $99-199/year from day one | Start at $35/year, prove the value, then introduce premium tiers |
| Add features users haven't requested | Build what the waitlist and beta users actually ask for |
| Avoid the PKM/second-brain vocabulary | Position around "structured" and "private" and "permanent" — not "knowledge management" |

---

## Summary Matrix (Updated)

| Dimension | Answer |
|-----------|--------|
| **Core Value** | Structured, private, offline-first thinking with immutable snapshots and reusable idea portals |
| **Killer Thesis** | *Obius is the notes app where every idea is a building block — structured, private, permanent, and yours.* |
| **Marketing Headline** | *Document how you think.* |
| **First Market** | Solo lawyers and independent legal professionals on iOS |
| **Second Market** | Academic researchers and PhD students |
| **Pricing** | Free tier + Pro at $34.99/year |
| **Key Launch Feature** | Auto-commits (passive reasoning trail) |
| **Biggest Threat** | Apple Notes getting "good enough" + second-brain market fatigue |
| **Phase 1 Target** | 500 downloads, 5-8% conversion to Pro |
| **Phase 2 Target** | 2,000 paying users, <5% monthly churn |
| **Phase 3 Target** | 10,000 paying users across 3+ professional verticals |
| **Phase 4** | Category transition to professional decision documentation (Year 2+) |
| **Moonshot 1** | Structured Thinking API (Month 8-10) |
| **Moonshot 2** | Cognitive Audit Trail (Month 10-14) |
| **Moonshot 3** | Portable Proof Layer (Month 14-18) |
| **Moonshot 4** | Living Knowledge Mesh (Month 18+) |
