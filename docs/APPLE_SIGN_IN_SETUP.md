# Apple Sign-In Setup (Native)

## Summary

Native Sign in with Apple using Supabase Auth via the official `supabase-swift` SDK.

## Configuration Checklist

- **Apple Developer**: App ID with Sign in with Apple capability; key with Sign in with Apple enabled (`2L8UB6KF64.com.jiayunzhao.LingoDex`)
- **Supabase Dashboard**: Auth → Providers → Apple enabled; Client IDs = `com.jiayunzhao.LingoDex`
- **Xcode**: Sign in with Apple entitlement in `LingoDex.entitlements`

## Implementation Details

### 1. Info.plist (required)

Xcode ignores user-defined `INFOPLIST_KEY_*` build settings. Use a real plist file:

- **Location**: `Info.plist` at project root (not inside `LingoDex/` — that triggers "Multiple commands produce" with `PBXFileSystemSynchronizedRootGroup`)
- **Keys**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- **Build setting**: `INFOPLIST_FILE = Info.plist`

### 2. supabase-swift SDK

- **Package**: `https://github.com/supabase/supabase-swift` (Supabase product)
- **Usage**: `SupabaseAuthClient` wraps `supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(...))`
- **Config**: Do not use `supabase.supabaseURL` / `supabase.supabaseKey` (internal). Read from `Bundle.main.object(forInfoDictionaryKey:)` or `ProcessInfo.processInfo.environment` instead.

### 3. Flow

1. `SignInWithAppleButton` + `ASAuthorizationAppleIDCredential` provide `idToken` and `nonce`
2. `SupabaseAuthClient.signInWithAppleIdToken` calls SDK’s `signInWithIdToken`
3. SDK handles `/auth/v1/token` and response parsing
4. Full name from first sign-in is saved via `supabase.auth.update(user: UserAttributes(data: ["full_name": .string(...)]))`

## Files

| File | Purpose |
|------|---------|
| `Info.plist` | SUPABASE_URL, SUPABASE_ANON_KEY |
| `LingoDex/App/Dependencies.swift` | Shared `SupabaseClient`, config from Info.plist |
| `LingoDex/Auth/SupabaseAuthClient.swift` | SDK wrapper, `isSupabaseConfigured` from Bundle |

## Troubleshooting

- **"Supabase is not configured"**: Info.plist missing keys or `INFOPLIST_FILE` not set
- **"Multiple commands produce"**: Info.plist is inside the synced `LingoDex/` folder — move to project root
- **"Data couldn't be read"**: Old custom token decoding; use supabase-swift SDK
