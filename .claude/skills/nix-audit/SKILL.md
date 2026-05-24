---
name: nix-audit
description: "Use when performing a security audit of the NixOS system. Runs vulnix, gitleaks, systemd-analyze security, checks failed units, and reviews closure size."
---

# NixOS Security Audit

Run all scanners and compile a report.

## Steps

1. **CVE scan** (against live closure):
   ```bash
   vulnix -S 2>&1 | head -100
   ```

2. **Secret detection** (in repo):
   ```bash
   gitleaks detect --no-banner --no-git
   ```

3. **Systemd hardening** (flag units scoring >5.0):
   ```bash
   systemd-analyze security 2>/dev/null | sort -t'.' -k1 -rn | head -20
   ```

4. **Failed units**:
   ```bash
   systemctl --failed
   ```

5. **Closure size** (baseline):
   ```bash
   nix path-info -Sh /run/current-system
   ```

6. **AppArmor status** (if active):
   ```bash
   aa-status 2>/dev/null | head -20
   ```

## Report Format
Compile findings into a table:

| Severity | Component | Finding | Remediation |
|----------|-----------|---------|-------------|
| High     | nginx     | CVE-... | Update nixpkgs |

## Rules
- Run ALL steps — do not skip
- Delegate to nix-security-auditor agent for deeper analysis
- Do not modify any files — audit is read-only
