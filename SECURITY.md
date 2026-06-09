# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email your findings to the project maintainers through a private channel
3. Include steps to reproduce the vulnerability
4. Allow reasonable time for a fix before public disclosure

## What This Project Does NOT Store

- No API keys or tokens are hardcoded in the source code
- No user credentials are collected or stored
- The Kolichka backend API is fully public and requires no authentication
- Location data is only used locally and never transmitted to third parties

## Configuration Security

The API base URL is configured at runtime via `--dart-define` flags:

```bash
flutter run --dart-define=FLUTTER_API_BASE_URL=https://kolichka.gotvach.com
```

Environment files (`.env`, `.env.local`) are gitignored and should never be committed.
