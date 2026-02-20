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

---

## 9. Intelligence Page: Insights Specification

### Design Principle

Every insight must pass the **"So What?" test**: if the user reads it and shrugs, it's noise. If they read it and immediately tap into a note, it's working.

Insights are not notifications. They are not metrics. They are **observations about your thinking that you didn't know you needed to see.** Each one has:
- A clear finding (what the AI/system noticed)
- A clear action (what the user can do about it)
- A link back to the source (notes/sections that produced the insight)

### Architecture: Two Surfaces

**Surface 1 — Editor Actions (contextual, inside the note):**
AI operates on the note you're currently editing. Accessed through the existing editor toolbar and section context menus. No new navigation.

**Surface 2 — Insights Feed (discovery, the Intelligence tab):**
A feed of insight cards generated by background analysis of your entire note collection. Each card is tappable and leads to specific notes/sections. This is the redesigned IntelligenceView.

---

### Surface 1: Editor Actions

These live inside NoteEditorView. They act on the current note.

#### E1. Suggest Title
- **Trigger:** Note has no user-set title, or user taps sparkle icon near title
- **What it does:** Calls `generate-summary` edge function, returns a title suggestion
- **Output:** Inline suggestion below the title field — tap to accept, swipe to dismiss
- **Data source:** All sections in the current note → Claude
- **Requires AI:** Yes (Claude)
- **Why it matters:** Untitled notes are invisible in search and lists. A good title makes a note findable.

#### E2. Summarize Note
- **Trigger:** Note menu (ellipsis) → "Summarize"
- **What it does:** Generates a 2-3 sentence summary of the note's content
- **Output:** Sheet with summary text, copy button, dismiss
- **Data source:** All sections in the current note → Claude
- **Requires AI:** Yes (Claude)
- **Why it matters:** Long notes become hard to remember. A summary is useful for sharing context with others or reminding yourself what a note contains.

#### E3. Auto-Tag Sections
- **Trigger:** Note menu → "Suggest Intent Tags"
- **What it does:** Analyzes untagged sections and suggests intent types (idea/question/task/evidence)
- **Output:** Preview showing each section with its suggested tag, highlighted in color. Accept all, accept individually, or dismiss.
- **Data source:** Section content → Claude (or local heuristic: sentences ending in "?" → Question, sentences starting with action verbs → Task)
- **Requires AI:** Partial (basic heuristic for v1, Claude for accuracy in v2)
- **Why it matters:** Intent tags are the foundation of most insights. The more sections are tagged, the smarter the Insights feed becomes. This creates a virtuous cycle.

#### E4. Find Related Sections
- **Trigger:** Section context menu (long press) → "Find Related"
- **What it does:** Searches all other notes for sections with high semantic similarity
- **Output:** Sheet listing matching sections, each showing the parent note title, a content preview, and similarity indicator. Tap to navigate to that note.
- **Data source:** Section embedding → pgvector cosine similarity
- **Requires AI:** Yes (OpenAI embeddings)
- **Why it matters:** You wrote something relevant in another note 3 weeks ago. You forgot. This finds it.

---

### Surface 2: Insights Feed

These appear as cards on the Intelligence tab. They're generated by background analysis. The user opens the tab and reviews what's waiting.

Organized into five categories based on what they reveal about the user's thinking.

---

#### Category 1: Gaps in Your Thinking

These insights surface incompleteness — questions without answers, evidence without conclusions, threads you started but didn't finish.

##### I1. Unanswered Questions
- **Finding:** "3 questions across 2 notes have no matching evidence"
- **Logic:** Find all sections tagged `Question`. For each, check if the same note contains at least one section tagged `Evidence`. If a note has Questions but no Evidence, it has unanswered questions.
- **Card shows:** Note titles and question section previews
- **Action:** Tap → navigate to the note, focused on the question sections
- **Requires AI:** No (local SQLite query on intent tags)
- **Why it matters:** This is the single most valuable insight for professionals. A lawyer with unanswered questions in a case brief has a gap in their reasoning. A researcher with questions but no evidence has unfounded claims. Surfacing this is immediately actionable.

##### I2. Unsupported Ideas
- **Finding:** "2 ideas have no supporting evidence"
- **Logic:** Find all sections tagged `Idea`. Check if the same note also contains `Evidence` sections. Ideas without evidence are unsupported assertions.
- **Card shows:** Note titles and idea section previews
- **Action:** Tap → navigate to the note
- **Requires AI:** No (local query)
- **Why it matters:** An idea without evidence is an opinion. Professionals need to back their thinking. This nudge helps them build stronger arguments.

##### I3. Orphaned Evidence
- **Finding:** "Evidence in 'Market Research' isn't connected to any idea or question"
- **Logic:** Notes that contain `Evidence` sections but no `Question` or `Idea` sections. The evidence exists but isn't framed by a question or supporting a thesis.
- **Card shows:** Note title and evidence section previews
- **Action:** Tap → navigate, with a suggestion to add a framing question
- **Requires AI:** No (local query)
- **Why it matters:** Evidence without context is just information. Framing it with a question or idea turns it into an argument.

##### I4. Open Tasks
- **Finding:** "7 tasks across 4 notes are still open"
- **Logic:** All sections tagged `Task` that haven't been marked complete (checklist items unchecked, or text sections with Task intent)
- **Card shows:** Task sections grouped by note, with preview text
- **Action:** Tap a task → navigate to the note. Optional: "Mark complete" inline.
- **Requires AI:** No (local query)
- **Why it matters:** Task sections scattered across notes are easy to lose. This is a lightweight task aggregator that doesn't replace a to-do app but surfaces commitments buried in thinking notes.

##### I5. Incomplete Reasoning Chain
- **Finding:** "'Patent Strategy' has questions and evidence but no conclusion"
- **Logic:** Notes that have `Question` AND `Evidence` sections but no `Idea` section. The research is done but no synthesis was captured.
- **Card shows:** Note title, count of questions answered by evidence, note that no idea/conclusion section exists
- **Action:** Tap → navigate, with a prompt to add a conclusion/synthesis section
- **Requires AI:** No (local query on intent distribution)
- **Why it matters:** This is the "you did the work but didn't capture the insight" nudge. For professionals who need to document their reasoning (lawyers, consultants, researchers), this is the most important gap to close.

---

#### Category 2: Connections You Missed

These insights surface relationships between notes that you didn't explicitly create.

##### I6. Concept Clusters
- **Finding:** "4 notes share the tag #patent-filing"
- **Logic:** Group notes by #tag. Surface clusters of 3+ notes sharing a tag, especially if they aren't already in the same note group.
- **Card shows:** Tag name, note titles, section count per note
- **Action:** Tap → view all notes in the cluster. Optional: "Create group" to organize them.
- **Requires AI:** No (local query on #tags)
- **Why it matters:** #tags are explicit concept markers. When multiple notes share a concept, the user may want to group them, merge them, or create Handle Loops between them.

##### I7. Similar Sections Across Notes
- **Finding:** "Sections in 'Client Brief' and 'Contract Review' discuss similar themes"
- **Logic:** Compute pairwise cosine similarity between section embeddings across different notes. Surface pairs above a threshold (e.g., 0.85).
- **Card shows:** Both section previews side by side, note titles, similarity score
- **Action:** Tap → view both notes. Optional: "Create Handle" to link them.
- **Requires AI:** Yes (OpenAI embeddings + pgvector)
- **Why it matters:** You wrote the same thing in two places without realizing it. Either consolidate via a Handle, or recognize the connection you didn't see.

##### I8. Tag Overlap
- **Finding:** "'Contract Law' and 'Liability Research' share 3 tags but aren't grouped"
- **Logic:** Find pairs of notes with high tag overlap (e.g., 3+ shared #tags) that aren't in the same group.
- **Card shows:** Both note titles, shared tags, unique tags for each
- **Action:** Tap → view both notes. Optional: "Group together"
- **Requires AI:** No (local query on #tags)
- **Why it matters:** High tag overlap suggests these notes are about the same topic. The user may want to consolidate or at least be aware of the overlap.

##### I9. Handle Candidates
- **Finding:** "'Filing deadline: March 15' appears verbatim in 3 notes — create a Handle?"
- **Logic:** Find near-identical text strings (or highly similar embeddings) that appear in sections across multiple notes but aren't linked via Handle Loops.
- **Card shows:** The repeated text, the notes it appears in
- **Action:** Tap → "Create Handle" to link them. Editing one will update all.
- **Requires AI:** Partial (exact string match for v1, embeddings for fuzzy matching in v2)
- **Why it matters:** This is the discovery mechanism for Handle Loops. Users who don't know about Handles will discover them through this insight. Users who do know will appreciate the automation.

---

#### Category 3: Evolution of Your Ideas

These insights surface how your thinking has changed over time, powered by commit history and auto-commits.

##### I10. Reasoning Evolution
- **Finding:** "'Patent Strategy' has evolved significantly — 12 auto-commits over 3 weeks"
- **Logic:** Notes with high commit frequency and significant content changes between commits (measured by content hash differences or section count changes).
- **Card shows:** Note title, commit count, date range, brief description of what changed (sections added/removed/modified)
- **Action:** Tap → view commit timeline for the note
- **Requires AI:** No (local query on commits table + content diff)
- **Why it matters:** Seeing that a note has been actively evolving reminds the user of their own progress. It's also valuable for the audit trail — "I've been developing this thinking for 3 weeks."

##### I11. Stale Notes
- **Finding:** "'Case Research — Davis' hasn't been touched in 21 days"
- **Logic:** Notes with recent content (edited in the last 60 days) that haven't been modified in the last 14+ days, especially if they contain open Tasks or unanswered Questions.
- **Card shows:** Note title, last edit date, count of open tasks/questions
- **Action:** Tap → navigate to the note. "Archive" if it's done, or re-engage.
- **Requires AI:** No (local query on timestamps)
- **Why it matters:** Stale notes with open tasks represent forgotten commitments. Stale notes with unanswered questions represent abandoned research. Either way, the user should decide: finish or close.

##### I12. Abandoned Threads
- **Finding:** "You added 3 sections to 'Market Analysis' 2 weeks ago but never developed them"
- **Logic:** Sections that were created (via auto-commit diff) but remain short (under 50 characters or a single line) and haven't been modified since creation. These are placeholders or stubs the user meant to fill in.
- **Card shows:** Note title, stub section previews, date added
- **Action:** Tap → navigate to the note, focused on the stub sections
- **Requires AI:** No (local query on sections + commit diffs)
- **Why it matters:** Stub sections are intentions that didn't become actions. Surfacing them reminds the user of what they planned to think about.

##### I13. Significant Changes
- **Finding:** "'Q1 Budget' changed substantially since your last manual commit"
- **Logic:** Compare the current note state to the most recent manual commit. If the section count, content length, or structure has changed significantly (e.g., >30% content change), surface it.
- **Card shows:** Note title, last commit date, summary of changes (sections added/removed/modified)
- **Action:** Tap → "Commit now" to snapshot the current state, or view the diff
- **Requires AI:** No (local diff between current state and last commit hash)
- **Why it matters:** Auto-commits capture the background trail. But a *manual* commit is an intentional checkpoint. This insight says "your thinking has moved far enough that it might be worth a deliberate snapshot."

---

#### Category 4: Readiness Signals

These insights surface notes that are ready for a next step — sharing, committing, exporting, or reviewing.

##### I14. Ready to Share
- **Finding:** "'Client Proposal' has a title, structured sections, and no open questions — ready to share?"
- **Logic:** Notes that have: a title (user-set or AI-generated), at least 3 sections, no unanswered Question sections, and at least one Evidence or Idea section. These look "complete."
- **Card shows:** Note title, section count, structure summary
- **Action:** Tap → open share sheet for this note
- **Requires AI:** No (local heuristic)
- **Why it matters:** Users often don't realize a note has reached a shareable state. This nudge converts private thinking into professional output.

##### I15. Uncommitted Work
- **Finding:** "3 notes have never been committed"
- **Logic:** Notes with content (at least 2 sections) that have zero entries in the commits table.
- **Card shows:** Note titles, section counts, last edit dates
- **Action:** Tap → "Commit all" or commit individually
- **Requires AI:** No (local query)
- **Why it matters:** Uncommitted notes have no history and no immutable snapshots. If the user values provenance, this is a gap in their trail.

##### I16. Echo Check-In
- **Finding:** "Your echo for 'Review patent filing' fires tomorrow"
- **Logic:** Echoes with next fire date within 24 hours, linked to their associated handles/notes.
- **Card shows:** Echo description, fire time, linked note
- **Action:** Tap → navigate to the linked note to prepare
- **Requires AI:** No (local query on echoes)
- **Why it matters:** Echoes are reminders, but seeing them in the Insights feed alongside other note-related insights creates a unified view of "what needs my attention."

##### I17. Shared Content Activity
- **Finding:** "'Contract Brief' commit link has been viewed 14 times"
- **Logic:** Share links with view counts that increased since the last time the user opened Insights.
- **Card shows:** Share link title/slug, view count, new views since last check, comment count
- **Action:** Tap → view shared content, read new comments
- **Requires AI:** No (local query on share links)
- **Why it matters:** When you share thinking, you want to know if people engage with it. This closes the sharing loop.

---

#### Category 5: Thinking Patterns

These insights surface meta-observations about how the user thinks — their habits, their style, and their blind spots.

##### I18. Intent Distribution
- **Finding:** "This week you created 12 Evidence sections but only 1 Idea section"
- **Logic:** Aggregate intent tags across all sections created in the last 7 days. Surface imbalances (heavy on one type, light on another).
- **Card shows:** Bar chart or simple counts of each intent type for the week
- **Action:** Tap → view the intent breakdown. Awareness insight — no specific navigation target.
- **Requires AI:** No (local aggregation)
- **Why it matters:** A professional who gathers evidence but never synthesizes ideas has a pattern worth noticing. A thinker who generates ideas but never gathers evidence has a different pattern. Neither is wrong — but awareness is valuable. This is the "mirror" insight.

##### I19. Concept Momentum
- **Finding:** "#patent-law is your most active concept this week (8 sections across 3 notes)"
- **Logic:** Rank #tags by section creation count in the last 7 days. Surface the top 1-3 concepts with momentum.
- **Card shows:** Tag name, section count, note count, trend vs. previous week
- **Action:** Tap → view all notes with this tag
- **Requires AI:** No (local aggregation on #tags)
- **Why it matters:** Knowing what you're *actually* spending cognitive energy on — vs. what you *think* you're working on — is a powerful self-awareness tool. Especially for professionals juggling multiple projects.

##### I20. Weekly Thinking Summary
- **Finding:** "This week: 4 notes edited, 18 sections created, 3 commits made, 2 questions answered"
- **Logic:** Aggregate weekly activity across notes, sections, commits, and intent tag transitions (question that now has evidence = "answered").
- **Card shows:** Clean summary with key numbers
- **Action:** Informational. Optional: "Commit weekly summary" to create a meta-snapshot.
- **Requires AI:** No (local aggregation)
- **Why it matters:** This is the lightest-weight insight but creates a habit loop. Users open the Intelligence tab on Monday to see their weekly summary. That habit drives discovery of the other, more actionable insights.

---

### Insight Priority Matrix

| # | Insight | Category | Requires AI | Build Difficulty | User Impact | Ship In |
|---|---------|----------|-------------|-----------------|-------------|---------|
| I1 | Unanswered Questions | Gaps | No | Easy | Very High | v1.0 |
| I4 | Open Tasks | Gaps | No | Easy | High | v1.0 |
| I11 | Stale Notes | Evolution | No | Easy | High | v1.0 |
| I15 | Uncommitted Work | Readiness | No | Easy | High | v1.0 |
| I6 | Concept Clusters | Connections | No | Easy | High | v1.0 |
| I20 | Weekly Thinking Summary | Patterns | No | Easy | Medium | v1.0 |
| I16 | Echo Check-In | Readiness | No | Easy | Medium | v1.0 |
| I17 | Shared Content Activity | Readiness | No | Easy | Medium | v1.0 |
| I5 | Incomplete Reasoning Chain | Gaps | No | Easy | Very High | v1.1 |
| I2 | Unsupported Ideas | Gaps | No | Easy | High | v1.1 |
| I3 | Orphaned Evidence | Gaps | No | Easy | Medium | v1.1 |
| I18 | Intent Distribution | Patterns | No | Easy | Medium | v1.1 |
| I19 | Concept Momentum | Patterns | No | Easy | Medium | v1.1 |
| I8 | Tag Overlap | Connections | No | Medium | Medium | v1.1 |
| I10 | Reasoning Evolution | Evolution | No | Medium | High | v1.2 |
| I13 | Significant Changes | Evolution | No | Medium | High | v1.2 |
| I14 | Ready to Share | Readiness | No | Medium | Medium | v1.2 |
| I12 | Abandoned Threads | Evolution | No | Medium | Medium | v1.2 |
| I9 | Handle Candidates | Connections | Partial | Medium | High | v1.2 |
| E1 | Suggest Title | Editor | Yes (Claude) | Easy | High | v1.0 |
| E3 | Auto-Tag Sections | Editor | Partial | Medium | High | v1.1 |
| E2 | Summarize Note | Editor | Yes (Claude) | Easy | Medium | v1.1 |
| I7 | Similar Sections | Connections | Yes (OpenAI) | Hard | High | v1.2 |
| E4 | Find Related Sections | Editor | Yes (OpenAI) | Hard | High | v1.2 |

### Key Observation

**14 of the 20 feed insights require zero AI API calls.** They are local SQLite queries on structured data — intent tags, #tags, timestamps, commit counts, section counts. This is the payoff of Obius's structured architecture: the data is already tagged, typed, and timestamped. The "intelligence" comes from querying what's already there, not from sending everything to a language model.

This means:
- The Insights feed can launch with rich, useful content on day one of Pro
- API costs are minimal (only 4 insights need AI at all, and those ship in v1.2)
- Insights work offline (local queries don't need internet)
- Insights are fast (SQLite queries, not API round-trips)

The AI features (semantic search, title suggestion, auto-tagging) are valuable additions layered on top — not the foundation. The foundation is the structured data the user already creates by using sections, intent tags, and #tags.

### Feed Refresh Strategy

- **On app foreground:** Recompute all local-query insights (I1-I6, I8, I10-I20). These are cheap SQLite queries.
- **On sync completion:** Recompute share activity (I17) and any embedding-based insights (I7, I9).
- **Daily background:** Generate the weekly summary snapshot (I20).
- **Never:** Auto-refresh AI-generated insights (titles, summaries). These only run when the user explicitly requests them via Editor Actions.

### Feed UX Rules

1. **Cap at 8-10 visible cards.** More than that becomes overwhelming. Prioritize by impact and recency.
2. **Dismissable.** Each card has a dismiss action. Dismissed insights don't reappear for that note until something changes.
3. **"New" badge.** Cards generated since the user's last visit show a subtle indicator.
4. **Empty state.** If all insights are dismissed or resolved: "Your thinking is in good shape. Check back later." This is a positive signal, not a dead page.
5. **No gamification.** No streaks, no points, no "you've committed 5 days in a row!" This is a professional tool, not a habit tracker.
