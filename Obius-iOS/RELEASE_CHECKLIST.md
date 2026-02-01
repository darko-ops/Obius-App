# Obius iOS Release Checklist

## Pre-Release Tasks

### Code Quality
- [ ] All unit tests passing
- [ ] No compiler warnings
- [ ] Static analyzer clean (Cmd+Shift+B)
- [ ] Memory leaks checked with Instruments
- [ ] Performance profiled (60fps target)

### Configuration
- [ ] Update version number in Info.plist
- [ ] Update build number
- [ ] Verify release xcconfig settings
- [ ] Confirm Supabase production credentials
- [ ] Disable debug logging

### Testing
- [ ] Test on all supported iOS versions (16.0+)
- [ ] Test on various device sizes
- [ ] Test offline functionality
- [ ] Test sync with real server
- [ ] Test auth flow (sign in, sign up, sign out)
- [ ] Test note creation and editing
- [ ] Test section reordering
- [ ] Test AI features (title generation, semantic search)
- [ ] Test error handling and recovery

### Security
- [ ] No hardcoded API keys
- [ ] No debug logs in release build
- [ ] App Transport Security enabled
- [ ] Keychain used for sensitive data

## App Store Connect

### App Information
- [ ] App name: Obius
- [ ] Subtitle: Local-first notes with AI
- [ ] Category: Productivity
- [ ] Age rating: 4+
- [ ] Copyright: © 2024 Obius

### Metadata
- [ ] Description (4000 chars max)
- [ ] Keywords (100 chars max, comma-separated)
- [ ] Support URL
- [ ] Marketing URL
- [ ] Privacy Policy URL

### Screenshots (Required)
- [ ] 6.7" (iPhone 15 Pro Max) - 1290 x 2796
- [ ] 6.5" (iPhone 14 Plus) - 1284 x 2778
- [ ] 5.5" (iPhone 8 Plus) - 1242 x 2208
- [ ] 12.9" iPad Pro - 2048 x 2732
- [ ] 11" iPad Pro - 1668 x 2388

### App Preview Videos (Optional)
- [ ] 30 seconds max
- [ ] Show key features
- [ ] No audio or voiceover required

## Build & Submit

### Archive
```bash
xcodebuild -scheme "Obius" -configuration Release archive
```

### Upload
- [ ] Archive build in Xcode
- [ ] Validate archive
- [ ] Upload to App Store Connect
- [ ] Wait for processing

### TestFlight
- [ ] Internal testing (team)
- [ ] External testing (beta users)
- [ ] Collect feedback
- [ ] Fix critical issues

### Submission
- [ ] Select build version
- [ ] Add release notes
- [ ] Answer export compliance questions
- [ ] Submit for review

## Post-Release

- [ ] Monitor crash reports
- [ ] Respond to reviews
- [ ] Track analytics
- [ ] Plan next release

## Version History

| Version | Build | Date | Notes |
|---------|-------|------|-------|
| 1.0.0   | 1     | TBD  | Initial release |

## App Store Description Template

```
Obius is a local-first notes app where your ideas live as structured, searchable sections.

KEY FEATURES

• Local-First: Your notes are always available, even offline
• Sections: Organize thoughts as collapsible, reorderable sections
• Smart Search: Find notes instantly with AI-powered semantic search
• AI Titles: Let AI generate meaningful titles for your notes
• Sync: Seamlessly sync across devices with conflict resolution
• Privacy: Your notes are encrypted and stored locally first

DESIGNED FOR THINKERS

Unlike traditional note apps, Obius treats each idea as a section that can be:
- Collapsed or expanded
- Reordered with drag and drop
- Nested with indent levels
- Color-coded by intent (idea, important, question, etc.)

WORKS OFFLINE

Take notes anywhere. Obius works completely offline and syncs when you're back online. No internet required to access your thoughts.

AI THAT ASSISTS, NOT CONTROLS

Optional AI features help you organize:
- Generate descriptive titles
- Create summaries
- Find related sections with semantic search

Your notes are yours. AI only runs when you ask it to.

PRIVACY FIRST

- Notes stored locally on device first
- End-to-end encrypted sync
- No data sold or shared
- Optional privacy mode (local only)
```

## Keywords Template

```
notes,local-first,offline,sections,organize,ai,sync,productivity,writing,ideas,semantic search,outline
```
