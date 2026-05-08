# Obius iOS Configuration

## Setup Instructions

### 1. Create Secrets File

Copy the template and fill in your credentials:

```bash
cp Secrets.xcconfig.template Secrets.xcconfig
```

Edit `Secrets.xcconfig` with your values:
- `SUPABASE_PROJECT_REF` - Your Supabase project reference
- `SUPABASE_ANON_KEY` - Your Supabase anonymous key
- `DEVELOPMENT_TEAM` - Your Apple Developer Team ID

### 2. Configure Xcode Project

In Xcode:
1. Select the Obius target
2. Go to Build Settings
3. Under "Configurations", set:
   - Debug → `Debug.xcconfig`
   - Release → `Release.xcconfig`

### 3. Include Secrets

Both Debug.xcconfig and Release.xcconfig should include:
```
#include "Secrets.xcconfig"
```

## Configuration Files

| File | Purpose |
|------|---------|
| `Debug.xcconfig` | Development build settings |
| `Release.xcconfig` | Production build settings |
| `Secrets.xcconfig` | API keys (gitignored) |
| `Info.plist` | App metadata with variable substitution |
| `AppConfiguration.swift` | Runtime access to configuration |

## Environment Variables

| Variable | Debug | Release |
|----------|-------|---------|
| `OBIUS_API_BASE_URL` | dev.obius.app | api.obius.app |
| `OBIUS_LOG_LEVEL` | debug | error |
| `OBIUS_ENABLE_ANALYTICS` | NO | YES |
| `PRODUCT_BUNDLE_IDENTIFIER` | app.obius.ios | app.obius.ios |

## Accessing Configuration in Code

```swift
// Environment
let isDebug = AppConfiguration.environment.isDebug

// Supabase
let url = AppConfiguration.supabaseURL
let key = AppConfiguration.supabaseAnonKey

// Version Info
let version = AppConfiguration.fullVersion

// Feature Flags
let aiEnabled = AppConfiguration.isAIEnabled
```

## Build Schemes

- **Obius Debug**: Local development, uses debug configuration
- **Obius Release**: Production build, uses release configuration

## Security Notes

- Never commit `Secrets.xcconfig` to version control
- Use environment variables in CI/CD for secrets
- The `.gitignore` file excludes sensitive files

## CI/CD Configuration

For CI/CD, set these environment variables:
- `SUPABASE_PROJECT_REF`
- `SUPABASE_ANON_KEY`
- `DEVELOPMENT_TEAM`
- `PROVISIONING_PROFILE_SPECIFIER`
