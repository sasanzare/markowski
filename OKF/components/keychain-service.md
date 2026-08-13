---
type: Swift Type
title: KeychainService
description: Stores and retrieves AI provider API keys via macOS Keychain Services, with a fallback for restricted environments.
resource: MarkView/Services/Security/KeychainService.swift
tags: [component, security, keychain]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

A singleton (`KeychainService.shared`) wrapping `SecItemAdd` /
`SecItemCopyMatching` / `SecItemDelete` under one `serviceName`
(`com.markview.app.apikeys`), keyed per call by an `account` string (see
`AIProviderType.keychainAccount` in [ai-provider](ai-provider.md)).
Items are stored with `kSecAttrAccessibleAfterFirstUnlock` and
`kSecUseDataProtectionKeychain: true`.

# Fallback path

If `SecItemAdd` fails (for example, Keychain access restricted in a
sandboxed/CI context), `saveKey` falls back to base64-encoding the value
into `UserDefaults` under `secure_<account>`; `getKey` checks the
Keychain first and falls back to that same `UserDefaults` key. This is a
deliberate degrade-gracefully choice, not a security boundary — the
`UserDefaults` fallback is not encrypted at rest.

# Save semantics

`saveKey` always deletes any existing entry for the account first
(`_ = try? deleteKey(...)`), so re-saving a key is idempotent rather than
erroring on `errSecDuplicateItem`.
