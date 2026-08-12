---
name: security-review
description: Use this skill when adding authentication, handling user input, working with secrets, creating API endpoints, or implementing payment/sensitive features. Provides comprehensive security checklist and patterns.
origin: ECC
---

# Security Review Skill

This skill ensures all code follows security best practices and identifies potential vulnerabilities.

Detailed code examples (FAIL/PASS patterns) for every category below live in
`reference.md`. This file holds the decision criteria: when to activate, the
checklist of categories, and the verification steps to check off.

## When to Activate

- Implementing authentication or authorization
- Handling user input or file uploads
- Creating new API endpoints
- Working with secrets or credentials
- Implementing payment features
- Storing or transmitting sensitive data
- Integrating third-party APIs

## Security Checklist

For each category, run through the verification steps below. See
`reference.md` for the corresponding FAIL/PASS code examples.

### 1. Secrets Management

- [ ] No hardcoded API keys, tokens, or passwords
- [ ] All secrets in environment variables
- [ ] `.env.local` in .gitignore
- [ ] No secrets in git history
- [ ] Production secrets in hosting platform (Vercel, Railway)

### 2. Input Validation

- [ ] All user inputs validated with schemas
- [ ] File uploads restricted (size, type, extension)
- [ ] No direct use of user input in queries
- [ ] Whitelist validation (not blacklist)
- [ ] Error messages don't leak sensitive info

See `reference.md#2-input-validation` for schema validation and file upload examples.

### 3. SQL Injection Prevention

- [ ] All database queries use parameterized queries
- [ ] No string concatenation in SQL
- [ ] ORM/query builder used correctly
- [ ] (Supabase のみ) Supabase queries properly sanitized

### 4. Authentication & Authorization

- [ ] Tokens stored in httpOnly cookies (not localStorage)
- [ ] Authorization checks before sensitive operations
- [ ] (Supabase のみ) Row Level Security enabled in Supabase
- [ ] Role-based access control implemented
- [ ] Session management secure

See `reference.md#4-authentication--authorization` for JWT handling, authorization checks, and Supabase RLS examples.

### 5. XSS Prevention

- [ ] User-provided HTML sanitized
- [ ] Security headers configured (CSP, X-Frame-Options; HTTPS enforced in production)
- [ ] No unvalidated dynamic content rendering
- [ ] React's built-in XSS protection used

See `reference.md#5-xss-prevention` for sanitization and CSP examples.

### 6. CSRF Protection

- [ ] CSRF tokens on state-changing operations
- [ ] SameSite=Strict on all cookies
- [ ] Double-submit cookie pattern implemented
- [ ] CORS properly configured

### 7. Rate Limiting

- [ ] Rate limiting on all API endpoints
- [ ] Stricter limits on expensive operations
- [ ] IP-based rate limiting
- [ ] User-based rate limiting (authenticated)

### 8. Sensitive Data Exposure

- [ ] No passwords, tokens, or secrets in logs
- [ ] Error messages generic for users
- [ ] Detailed errors only in server logs
- [ ] No stack traces exposed to users

See `reference.md#8-sensitive-data-exposure` for logging and error-message examples.

### 9. Blockchain Security (Solana、該当プロジェクトのみ)

- [ ] Wallet signatures verified
- [ ] Transaction details validated
- [ ] Balance checks before transactions
- [ ] No blind transaction signing

See `reference.md#9-blockchain-security-solana` for wallet and transaction verification examples.

### 10. Dependency Security

- [ ] Dependencies up to date
- [ ] No known vulnerabilities (npm audit clean)
- [ ] Lock files committed
- [ ] Dependabot enabled on GitHub
- [ ] Regular security updates

## Security Testing

Cover authentication, authorization, input validation, and rate limiting with
automated tests. See `reference.md#security-testing` for example test cases.

## Pre-Deployment Security Checklist

Before ANY production deployment, re-run the full Security Checklist above (all 10
categories) — every item in it applies at deploy time, not just during
implementation.

## Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Next.js Security](https://nextjs.org/docs/security)
- [Supabase Security](https://supabase.com/docs/guides/auth)
- [Web Security Academy](https://portswigger.net/web-security)
