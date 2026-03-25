# Incident Response Plan: Package & Container Registry Compromise

**Purpose**: Define procedures for preparing for, detecting, containing, eradicating, recovering from, and learning from supply chain incidents affecting packages and container images managed through GitLab and associated caching proxies.

**Framework**: This plan follows the [NIST SP 800-61r2](https://csrc.nist.gov/publications/detail/sp/800-61/rev-2/final) incident response lifecycle and aligns with the [CISA Incident Response Playbook](https://www.cisa.gov/sites/default/files/publications/Federal_Government_Cybersecurity_Incident_and_Vulnerability_Response_Playbooks_508C.pdf).

---

## Table of Contents

1. [Severity Classification](#1-severity-classification)
2. [Phase 1: Preparation](#2-phase-1-preparation)
3. [Phase 2: Identification](#3-phase-2-identification)
4. [Phase 3: Containment](#4-phase-3-containment)
5. [Phase 4: Eradication](#5-phase-4-eradication)
6. [Phase 5: Recovery](#6-phase-5-recovery)
7. [Phase 6: Post-Incident Activity](#7-phase-6-post-incident-activity)
8. [Scenario-Specific Runbooks](#8-scenario-specific-runbooks)
9. [Communication Templates](#9-communication-templates)
10. [Contacts & Escalation](#10-contacts--escalation)

---

## 1. Severity Classification

| Severity | Criteria | Response Time | Examples |
|---|---|---|---|
| **SEV-1 (Critical)** | Compromised package deployed to production; active exploitation | Immediate (< 15 min) | Backdoored dependency in prod, leaked secrets via malicious package |
| **SEV-2 (High)** | Compromised package in registry but not yet deployed; or deployed to non-prod only | < 1 hour | Typosquatted package installed in CI, malicious image in staging |
| **SEV-3 (Medium)** | Vulnerability disclosed in a dependency; no evidence of exploitation | < 4 hours | CVE published for a cached package, upstream maintainer compromise reported |
| **SEV-4 (Low)** | Policy violation; no security impact | < 24 hours | Unapproved package in registry, expired token still in use |

---

## 2. Phase 1: Preparation

Preparation is the foundation of effective incident response. This phase establishes the policies, roles, tools, and training needed **before** an incident occurs.

### 2.1 Roles & Responsibilities

Define and assign these roles. Each must have a named primary and backup:

| Role | Responsibility | Required Access |
|---|---|---|
| **Incident Commander (IC)** | Owns the incident lifecycle; coordinates all response activities; makes escalation decisions | GitLab Admin, Slack/Comms |
| **Security Analyst** | Triages alerts, performs forensic analysis, determines blast radius | GitLab API, SIEM, registry logs |
| **Registry Operator** | Executes containment actions on devpi, Verdaccio, GitLab registries | devpi admin, Verdaccio admin, GitLab Maintainer |
| **Infrastructure Engineer** | Applies network blocks, manages firewall rules, restores backups | Firewall admin, Docker host access |
| **Communications Lead** | Drafts and sends internal/external notifications | Email, Slack, status page |
| **Engineering Liaison** | Coordinates with affected development teams for remediation | Project-level GitLab access |

> **Action item**: Populate the [Contacts & Escalation](#10-contacts--escalation) table with your organization's specific names and contact methods.

### 2.2 Policies & Documentation

Ensure the following are documented, approved, and accessible to all responders:

- [ ] **This Incident Response Plan**: stored in a known location (e.g., GitLab wiki, Confluence), reviewed quarterly.
- [ ] **Package Allowlist Policy**: defines the approval process for adding packages to `config/approved-packages.txt`. See [security-scanning.gitlab-ci.yml](../cicd/security-scanning.gitlab-ci.yml).
- [ ] **Token & Credential Management Policy**: defines token scopes, rotation schedules, and storage requirements. Reference: [GitLab Token Overview](https://docs.gitlab.com/ee/security/token_overview.html).
- [ ] **Image Provenance Policy**: requires Cosign signatures and SBOM generation for all production images. See [docker-build-sign-push.gitlab-ci.yml](../cicd/docker-build-sign-push.gitlab-ci.yml).
- [ ] **Dependency Pinning Policy**: requires lockfiles with hashes for all production deployments.
- [ ] **CODEOWNERS rules**: enforces merge request approval for changes to dependency files, Dockerfiles, and CI/CD pipelines. Reference: [GitLab CODEOWNERS](https://docs.gitlab.com/ee/user/project/codeowners/).

### 2.3 Tooling

The following tools must be deployed, configured, and tested before an incident occurs:

#### Detection & Monitoring

| Tool | Purpose | Deployment |
|---|---|---|
| [GitLab Dependency Scanning](https://docs.gitlab.com/ee/user/application_security/dependency_scanning/) | CVE detection in Python/npm dependencies | CI/CD pipeline (every MR + nightly) |
| [GitLab Container Scanning](https://docs.gitlab.com/ee/user/application_security/container_scanning/) | Vulnerability detection in Docker image layers | CI/CD pipeline (every MR + nightly) |
| [Trivy](https://trivy.dev/) | CVE scanning for images, filesystems, repos | CI/CD pipeline + on-demand CLI |
| [Safety](https://safetycli.com/) / [pip-audit](https://pypi.org/project/pip-audit/) | Python-specific CVE databases | CI/CD pipeline |
| [npm audit](https://docs.npmjs.com/cli/v10/commands/npm-audit) | npm advisory database | CI/CD pipeline |
| [Gitleaks](https://gitleaks.io/) | Secret detection in source code | CI/CD pipeline (every MR) |
| [Semgrep](https://semgrep.dev/) | SAST scanning | CI/CD pipeline (every MR) |
| Package allowlist check | Blocks unapproved packages | CI/CD pipeline |

#### SIEM / SOAR Integration (recommended)

If your organization uses a SIEM (Security Information and Event Management) or SOAR (Security Orchestration, Automation, and Response) platform, integrate the following log sources:

- **GitLab Audit Events** -> SIEM. Reference: [GitLab Audit Event Streaming](https://docs.gitlab.com/ee/administration/audit_event_streaming.html).
- **devpi access logs** (`/var/log/devpi/access.log`) -> SIEM.
- **Verdaccio access logs** -> SIEM.
- **GitLab CI/CD pipeline events** -> SIEM (via webhooks or API polling).
- **Docker daemon logs** -> SIEM.

SOAR playbooks should automate:
- Alert triage for known CVEs (auto-create GitLab issues).
- Token expiration alerts (auto-notify token owners).
- Anomalous download pattern detection (auto-alert Security Analyst).

#### Forensic & Response Tools

Ensure these are pre-installed on responder workstations or available as Docker images:

```bash
# Forensic analysis
pip install safety pip-audit cyclonedx-bom
npm install -g @cyclonedx/cyclonedx-npm

# Image inspection
# Trivy: https://trivy.dev/latest/getting-started/installation/
# Syft (SBOM generation): https://github.com/anchore/syft
# Grype (vulnerability scanning): https://github.com/anchore/grype
# Cosign (signature verification): https://docs.sigstore.dev/cosign/installation/

# GitLab API access
# Ensure curl and jq are available
# Pre-configure a PRIVATE-TOKEN with admin scope for emergency use
```

### 2.4 Training & Drills

- **Quarterly tabletop exercises**: Walk through a hypothetical supply chain compromise scenario with all role holders. Rotate scenarios across Python packages, npm packages, Docker images, and credential leaks.
- **Annual red team drill**: Simulate a dependency confusion or typosquatting attack against your internal registries in a staging environment. Measure time-to-detect and time-to-contain.
- **Onboarding**: All new engineers review this IRP and the package allowlist policy within their first two weeks.
- **Runbook validation**: After each drill or real incident, verify that all commands in [Section 8](#8-scenario-specific-runbooks) execute correctly against the current infrastructure.

### 2.5 Backup & Recovery Readiness

| Asset | Backup Method | Frequency | Retention | Recovery Target |
|---|---|---|---|---|
| devpi data volume | Volume snapshot / `rsync` | Daily | 30 days | < 1 hour |
| Verdaccio data volume | Volume snapshot / `rsync` | Daily | 30 days | < 1 hour |
| GitLab Package Registry | GitLab backup (`gitlab-backup create`) | Daily | 14 days | < 4 hours |
| GitLab Container Registry | Object storage replication (S3/GCS) | Continuous | 90 days | < 2 hours |
| Approved packages list | Git version history | Every commit | Indefinite | < 5 minutes |
| Cosign signing keys | Encrypted offline storage (HSM or vault) | On creation | Indefinite | < 30 minutes |

> **Test restores quarterly.** A backup that has never been tested is not a backup.

---

## 3. Phase 2: Identification

Detect and confirm incidents by analyzing alerts, logs, and behavioral patterns. The goal is to determine whether an event is a true security incident and assess its initial scope.

### 3.1 Automated Detection Sources

These should be running on every CI/CD pipeline and on a nightly schedule:

| Source | What It Detects | Pipeline Reference |
|---|---|---|
| [GitLab Dependency Scanning](https://docs.gitlab.com/ee/user/application_security/dependency_scanning/) | Known CVEs in Python/npm dependencies | `security-scanning.gitlab-ci.yml` |
| [GitLab Container Scanning](https://docs.gitlab.com/ee/user/application_security/container_scanning/) | Vulnerabilities in Docker image layers | `security-scanning.gitlab-ci.yml` |
| [Trivy](https://trivy.dev/) | CVEs in images, filesystems, repos | `security-scanning.gitlab-ci.yml` |
| [Safety](https://safetycli.com/) / [pip-audit](https://pypi.org/project/pip-audit/) | Python-specific CVE database | `security-scanning.gitlab-ci.yml` |
| [npm audit](https://docs.npmjs.com/cli/v10/commands/npm-audit) | npm advisory database | `security-scanning.gitlab-ci.yml` |
| Package allowlist check | Unapproved packages entering the build | `security-scanning.gitlab-ci.yml` |
| [GitLab Secret Detection](https://docs.gitlab.com/ee/user/application_security/secret_detection/) | Leaked credentials in source code | Built-in GitLab feature |
| [Gitleaks](https://gitleaks.io/) | Leaked secrets (Free-tier alternative) | `security-scanning.gitlab-ci.yml` |

### 3.2 Manual & External Detection

- **Upstream advisories**: Monitor [PyPI Advisory Database](https://github.com/pypa/advisory-database), [npm Security Advisories](https://github.com/advisories), [Docker Hub security notices](https://docs.docker.com/docker-hub/).
- **Threat intelligence feeds**: Subscribe to [CISA Known Exploited Vulnerabilities](https://www.cisa.gov/known-exploited-vulnerabilities-catalog), [OSV.dev](https://osv.dev/), [OpenSSF Package Analysis](https://github.com/ossf/package-analysis).
- **GitLab Audit Log**: Review at **Settings > General > Audit Events** for unexpected package publishes, deletions, or permission changes.
- **devpi/Verdaccio access logs**: Monitor for unusual patterns:
  - Downloads of packages not in the allowlist.
  - Spikes in download volume for a single package.
  - Requests from unexpected IP ranges.
- **User reports**: Engineers reporting unexpected behavior after a dependency update.

### 3.3 Triage & Confirmation

When an alert fires or a report is received, the Security Analyst performs initial triage:

```
1. Is this a known false positive?
   -> YES: Document and close. Update detection rules if recurring.
   -> NO: Continue.

2. Is the affected package/image in our registry or cache?
   -> NO: Informational only. Log and monitor.
   -> YES: Continue.

3. Has the affected version been installed or deployed anywhere?
   -> Query devpi/Verdaccio logs and CI/CD pipeline logs.
   -> Check lockfiles across all projects (GitLab search API).
   -> If YES: Escalate. Assign severity per Section 1. Proceed to Containment.
   -> If NO (only in cache, never installed): SEV-3 or SEV-4. Proceed to Containment.

4. Assign an Incident Commander. Open a dedicated Slack channel / incident ticket.
```

### 3.4 Indicators of Compromise (IOCs) Specific to Supply Chain

| IOC | Where to Look |
|---|---|
| New package version with significantly different file size | devpi/Verdaccio storage, `pip download --no-deps` |
| Package with `setup.py` executing network calls or shell commands at install time | Source inspection, Semgrep rules |
| Docker image with unexpected new layers or changed layer digests | `docker history`, `cosign verify`, Trivy |
| GitLab API calls from unexpected IP addresses or with revoked tokens | GitLab Audit Events |
| Package name differing by one character from a popular package (typosquatting) | Allowlist enforcement, manual review |
| Sudden spike in download count for an internal package from external IPs | devpi/Verdaccio logs |

---

## 4. Phase 3: Containment

Isolate affected systems to prevent further spread. The goal is to stop the bleeding without destroying forensic evidence.

### 4.1 Immediate Containment (Short-Term)

Execute within the response time defined by the severity level.

#### Registry-Level Containment

```bash
# ── GitLab Package Registry ──
# Find the compromised package ID
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/packages?package_name=<compromised-package>"

# Delete the specific package version
curl --request DELETE \
  --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/packages/<PACKAGE_ID>"

# ── devpi ──
devpi use http://devpi.internal:3141/root/pypi
devpi remove <compromised-package>==<compromised-version>

# ── Verdaccio ──
# Remove from storage and restart to clear in-memory cache
rm -rf /verdaccio/storage/<compromised-package>
docker restart verdaccio

# ── GitLab Container Registry ──
# Find the repository ID
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/registry/repositories"

# Delete the compromised image tag
curl --request DELETE \
  --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/registry/repositories/<REPO_ID>/tags/<compromised-tag>"
```

#### Network-Level Containment

```bash
# Block the compromised package at the proxy level
echo "<compromised-package>" >> config/blocked-packages.txt

# If the attack vector is an upstream registry compromise,
# temporarily block all traffic to the upstream:
# (Use with caution; this stops all package resolution)
# iptables -A OUTPUT -d pypi.org -j DROP        # Linux firewall
# Or update devpi/Verdaccio config to disable upstream proxy
```

#### CI/CD Containment

```bash
# Pause all pipelines that depend on the compromised package
# GitLab API: cancel running pipelines
curl --request POST \
  --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/pipelines/<PIPELINE_ID>/cancel"
```

### 4.2 Evidence Preservation

**Before** eradicating, preserve forensic evidence:

```bash
# Snapshot the compromised package for analysis
pip download <compromised-package>==<compromised-version> \
  --no-deps -d /tmp/forensics/ \
  --index-url http://devpi.internal:3141/root/pypi/+simple/ 2>/dev/null || true

# Save the Docker image layers
docker save <compromised-image>:<tag> | gzip > /tmp/forensics/compromised-image.tar.gz

# Export relevant logs
cp /var/log/devpi/access.log /tmp/forensics/devpi-access.log
docker logs verdaccio > /tmp/forensics/verdaccio.log 2>&1

# Export GitLab audit events for the incident window
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/audit_events?created_after=<incident-start-date>" \
  > /tmp/forensics/gitlab-audit-events.json

# Timestamp and hash all forensic artifacts
find /tmp/forensics/ -type f -exec sha256sum {} \; > /tmp/forensics/manifest.sha256
```

### 4.3 Blast Radius Assessment

Determine which projects, services, and environments consumed the compromised artifact:

```bash
# Search all GitLab projects for references to the package
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/search?scope=blobs&search=<compromised-package>"

# Check CI/CD pipeline logs for recent installs of the package
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/pipelines?status=success&updated_after=<date>"

# Check devpi download logs
grep "<compromised-package>" /var/log/devpi/access.log

# For Docker images: check which services are running the compromised image
docker ps --filter "ancestor=<compromised-image>" --format '{{.ID}} {{.Names}} {{.Image}}'
```

Key questions to answer:
- Was the compromised version actually **installed** (present in a lockfile) or just **available** in the registry?
- Was it used in **production builds** or only in development/CI?
- Does the malicious code execute at **install time** (`setup.py`, `postinstall`) or at **runtime**?
- Were any **secrets, tokens, or credentials** accessible to the compromised package?
- How many **teams, projects, and environments** are affected?

---

## 5. Phase 4: Eradication

Remove the threat completely and address the vulnerability that was exploited.

### 5.1 Remove Malicious Artifacts

```bash
# Verify the compromised version is fully removed from all registries
# GitLab Package Registry
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/packages?package_name=<compromised-package>" \
  | jq '.[] | select(.version == "<compromised-version>")'
# Expected: empty result

# devpi
devpi list <compromised-package> 2>/dev/null
# Expected: compromised version not listed

# Verdaccio
ls /verdaccio/storage/<compromised-package>/
# Expected: directory does not exist or compromised version tarball absent

# GitLab Container Registry
curl --header "PRIVATE-TOKEN: <token>" \
  "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/registry/repositories/<REPO_ID>/tags" \
  | jq '.[] | select(.name == "<compromised-tag>")'
# Expected: empty result
```

### 5.2 Patch the Vulnerability

Identify **how** the compromised artifact entered your registry and close that vector:

| Entry Vector | Eradication Action |
|---|---|
| **Upstream package compromised** | Pin to a known-good version with hash verification. Add the compromised version to a deny list. |
| **Typosquatting / dependency confusion** | Add the legitimate package name to the allowlist. Reserve the internal package name on the public registry. Block the typosquatted name. |
| **Compromised maintainer credentials** | Rotate all tokens. Enable 2FA enforcement. Review and tighten token scopes. |
| **CI/CD pipeline manipulation** | Audit pipeline definitions. Enforce protected branches and merge request approvals for `.gitlab-ci.yml` changes. |
| **Malicious base Docker image** | Pin base images by digest (`FROM python@sha256:<digest>`). Rebuild all derived images with `--no-cache`. |

### 5.3 Credential Rotation

If any credentials may have been exposed:

```bash
# Revoke compromised tokens
# Via GitLab UI: Settings > Access Tokens > Revoke
# Via API:
curl --request DELETE \
  --header "PRIVATE-TOKEN: <admin-token>" \
  "https://gitlab.example.com/api/v4/personal_access_tokens/<TOKEN_ID>"

# Rotate all tokens accessible to the compromised package/environment:
# - GitLab personal/project/group access tokens
# - CI/CD variables containing secrets
# - Docker registry credentials
# - devpi/Verdaccio admin credentials
# - API keys stored in environment variables
# - Database connection strings

# Audit token usage during the compromise window
curl --header "PRIVATE-TOKEN: <admin-token>" \
  "https://gitlab.example.com/api/v4/audit_events?created_after=<token-creation-date>" \
  | jq '.[] | select(.details.custom_message | contains("token"))'
```

### 5.4 Update Lockfiles Across All Affected Projects

```bash
# Python: pin to a known-good version with hash verification
# requirements.txt
<package-name>==<known-good-version> --hash=sha256:<known-good-hash>

# npm: pin to a known-good version
npm install <package>@<known-good-version> --save-exact
rm package-lock.json && npm install
```

---

## 6. Phase 5: Recovery

Restore systems from clean state, validate integrity, and monitor for recurrence.

### 6.1 Rebuild & Redeploy

```bash
# Rebuild all affected Docker images from scratch (no layer cache)
docker build --no-cache -t $CI_REGISTRY_IMAGE:remediated .

# Redeploy affected services
# Use your standard deployment pipeline, but verify:
# 1. The lockfile contains only the known-good version
# 2. The Docker image was built from the patched lockfile
# 3. Cosign signature is valid on the new image
cosign verify --key cosign.pub $CI_REGISTRY_IMAGE:remediated
```

### 6.2 Validate Integrity

```bash
# Scan the rebuilt image
trivy image --severity HIGH,CRITICAL $CI_REGISTRY_IMAGE:remediated

# Verify the known-good package version
pip download <package>==<known-good-version> -d /tmp/verify --no-deps
pip-audit --requirement /tmp/verify/<package-file> || true
safety check --file /tmp/verify/<package-file> || true

# Generate a fresh SBOM for the remediated build
syft $CI_REGISTRY_IMAGE:remediated -o cyclonedx-json > sbom-remediated.json
```

### 6.3 Restore from Backups (if needed)

If registry data was corrupted or needs to be rolled back:

```bash
# devpi: restore from volume snapshot
docker stop devpi
# Restore the devpi-data volume from the most recent clean snapshot
docker start devpi

# Verdaccio: restore from volume snapshot
docker stop verdaccio
# Restore the verdaccio-data volume
docker start verdaccio

# GitLab: restore from backup (self-hosted)
# Reference: https://docs.gitlab.com/ee/administration/backup_restore/restore_gitlab.html
sudo gitlab-backup restore BACKUP=<timestamp>
```

### 6.4 Monitoring for Recurrence

After recovery, increase monitoring intensity for 30 days:

- [ ] Run dependency scans **twice daily** (increase nightly schedule to also run at noon).
- [ ] Enable verbose logging on devpi and Verdaccio.
- [ ] Set SIEM alerts for any download of the compromised package name (any version).
- [ ] Monitor GitLab Audit Events for any new token creation or permission changes.
- [ ] Review CI/CD pipeline logs daily for unexpected dependency changes.

### 6.5 Staged Restoration

Restore services in order of risk, not urgency:

```
1. Internal/staging environments first
   -> Run full test suites against remediated builds
   -> Verify no anomalous behavior in logs

2. Pre-production / canary
   -> Deploy to a subset of production traffic
   -> Monitor error rates, latency, and log anomalies for 24 hours

3. Full production rollout
   -> Deploy incrementally (rolling update)
   -> Maintain the previous known-good deployment as a rollback target
```

---

## 7. Phase 6: Post-Incident Activity

Conduct a thorough review, document lessons learned, update policies, and refine this plan.

### 7.1 Blameless Post-Incident Review

Conduct within **48 hours** of declaring the incident resolved. Include all role holders from the response.

**Agenda:**

1. **Timeline reconstruction**: Build a precise, timestamped sequence of events from detection to resolution.
2. **Detection gap analysis**: How long was the compromised artifact available before detection? What detection mechanism caught it? What mechanisms missed it?
3. **Blast radius review**: Could the impact have been limited through better isolation, least-privilege access, network segmentation, or dependency pinning?
4. **Process evaluation**: Were runbooks followed? Where did the process break down? Where were ad-hoc decisions made that should become documented procedures?
5. **Tooling assessment**: Did detection, containment, and forensic tools perform as expected? Are new tools or integrations needed?
6. **Communication review**: Were the right people notified at the right time? Were stakeholders kept informed?

### 7.2 Document Lessons Learned

Produce a post-incident report (see [Communication Templates](#9-communication-templates)) that includes:

- Root cause analysis
- Full timeline with timestamps
- Impact assessment (systems, teams, data, duration)
- What went well
- What needs improvement
- Action items with owners and deadlines

### 7.3 Update Policies & Procedures

Based on lessons learned:

- [ ] Update this Incident Response Plan with new runbook steps or corrections.
- [ ] Update the package allowlist (`config/approved-packages.txt`).
- [ ] Update scanning rules and SIEM detection logic.
- [ ] Update CI/CD pipeline templates if new scanning steps are needed.
- [ ] Update the CODEOWNERS file if approval gates were insufficient.
- [ ] Update token rotation schedules if credential hygiene was a factor.
- [ ] Schedule additional training if process gaps were people-related.

### 7.4 Review Checklist

- [ ] Timeline documented with exact timestamps
- [ ] Root cause identified and confirmed
- [ ] All affected systems identified and remediated
- [ ] Credentials rotated where necessary
- [ ] Scanning rules updated to detect similar attacks
- [ ] Package allowlist reviewed and updated
- [ ] This incident response plan updated with lessons learned
- [ ] Action items assigned with owners and deadlines
- [ ] Post-incident report distributed to stakeholders
- [ ] Next tabletop exercise scheduled

### 7.5 Metrics to Track

Track these metrics over time to measure IRP effectiveness:

| Metric | Definition | Target |
|---|---|---|
| **Mean Time to Detect (MTTD)** | Time from compromise to first alert | < 1 hour |
| **Mean Time to Contain (MTTC)** | Time from first alert to containment complete | < 30 minutes |
| **Mean Time to Recover (MTTR)** | Time from containment to full production recovery | < 4 hours |
| **Blast radius** | Number of projects/services affected | Decreasing trend |
| **False positive rate** | Percentage of alerts that are not true incidents | < 10% |
| **Drill frequency** | Tabletop exercises per year | >= 4 |

---

## 8. Scenario-Specific Runbooks

### 8.1 Compromised Python Package

**Trigger**: A Python package in your GitLab registry or devpi cache is identified as malicious or compromised.

| Phase | Actions |
|---|---|
| **Identify** | Confirm via Safety/pip-audit/Trivy. Check if the version is in any lockfile: `grep <package>==<version> **/requirements.txt`. |
| **Contain** | Remove from GitLab Package Registry (API DELETE). Purge from devpi (`devpi remove`). Block at proxy level. Cancel running pipelines. |
| **Eradicate** | Pin all projects to a known-good version with `--hash`. Rotate exposed credentials. Update allowlist. Reserve name on public PyPI if dependency confusion. |
| **Recover** | Rebuild and redeploy all affected services. Validate with `safety check` and `pip-audit`. Generate fresh SBOMs. |

### 8.2 Compromised npm Package

**Trigger**: An npm package in your GitLab registry or Verdaccio cache is identified as malicious.

| Phase | Actions |
|---|---|
| **Identify** | Confirm via `npm audit` or Trivy. Search for the package in `package-lock.json` files across projects. |
| **Contain** | Remove from GitLab npm Registry (API DELETE). Purge from Verdaccio (`rm -rf /verdaccio/storage/<pkg>` + restart). Cancel running pipelines. |
| **Eradicate** | `npm install <pkg>@<safe-version> --save-exact`. Regenerate lockfiles. Rotate exposed credentials. |
| **Recover** | Rebuild, redeploy, validate. Run `npm audit` on all remediated projects. |

### 8.3 Compromised Docker Image

**Trigger**: A Docker image in your GitLab Container Registry or pulled through the Dependency Proxy is compromised.

| Phase | Actions |
|---|---|
| **Identify** | Confirm via Trivy/Grype. Check `docker ps` for running containers using the image. Check CI/CD for builds using the image as a base. |
| **Contain** | Delete the tag from GitLab Container Registry (API DELETE). Purge from Dependency Proxy (GitLab UI). Stop running containers using the image. |
| **Eradicate** | Pin base images by digest: `FROM python@sha256:<known-good-digest>`. Rebuild all derived images with `--no-cache`. Rotate credentials. |
| **Recover** | Push rebuilt images. Redeploy services. Verify with `cosign verify`. Monitor for 30 days. |

### 8.4 Credential / Token Compromise

**Trigger**: A registry access token, CI/CD variable, or signing key is leaked.

| Phase | Actions |
|---|---|
| **Identify** | Determine token scope, creation date, and which systems used it. Check GitLab Audit Events for the token's activity. |
| **Contain** | Revoke the token immediately (GitLab UI or API). If a signing key: rotate the key pair and re-sign all images signed with the old key. |
| **Eradicate** | Generate new tokens with minimum required scopes. Update all systems: CI/CD variables, `~/.netrc`, `.npmrc`, Docker credentials. Enable 2FA if not already enforced. |
| **Recover** | Verify all systems function with new credentials. Audit for any unauthorized actions taken with the compromised token during the exposure window. |

---

## 9. Communication Templates

### Internal Alert (SEV-1 / SEV-2)

```
SUBJECT: [SECURITY] Compromised package detected - <package-name>@<version>

SEVERITY: SEV-<N>
DETECTED: <timestamp>
INCIDENT COMMANDER: <name>
PACKAGE: <package-name> version <version>
REGISTRY: <GitLab / devpi / Verdaccio>
STATUS: <Identified / Contained / Eradicating / Recovering>

SUMMARY:
<Brief description of the compromise and how it was detected>

AFFECTED SYSTEMS:
- <List of projects/services consuming the package>

IMMEDIATE ACTIONS TAKEN:
- <Package removed from registry>
- <Network block applied>
- <Running pipelines cancelled>

REQUIRED ACTIONS:
- [ ] All teams using <package-name>: pin to version <safe-version> immediately
- [ ] Rebuild and redeploy affected services
- [ ] Rotate any credentials accessible to the compromised package

NEXT UPDATE: <timestamp>
SLACK CHANNEL: #incident-<name>
```

### Post-Incident Summary

```
SUBJECT: [RESOLVED] Post-Incident Report - <package-name> compromise

INCIDENT ID: <ID>
SEVERITY: SEV-<N>
DURATION: <start> to <end> (<total hours>)
INCIDENT COMMANDER: <name>

TIMELINE:
- <T+0>:   Compromise introduced upstream / in registry
- <T+X>:   Alert fired / report received (DETECTION)
- <T+Y>:   Incident confirmed, IC assigned (IDENTIFICATION)
- <T+Z>:   Package removed, pipelines cancelled (CONTAINMENT)
- <T+W>:   Lockfiles patched, credentials rotated (ERADICATION)
- <T+V>:   Services rebuilt and redeployed (RECOVERY)
- <T+U>:   All-clear issued

ROOT CAUSE:
<Description of how the compromise occurred and entered the registry>

IMPACT:
- <Number of affected projects/services>
- <Duration of exposure>
- <Data/credential exposure assessment>
- <Customer impact, if any>

WHAT WENT WELL:
- <Positive aspects of the response>

WHAT NEEDS IMPROVEMENT:
- <Gaps or delays in the response>

CORRECTIVE ACTIONS:
- [ ] <Action 1>: Owner: <name>, Due: <date>
- [ ] <Action 2>: Owner: <name>, Due: <date>
- [ ] <Action 3>: Owner: <name>, Due: <date>
```

---

## 10. Contacts & Escalation

> **Customize this section for your organization.**

| Role | Contact | Escalation Trigger |
|---|---|---|
| On-call Engineer | `#oncall` Slack channel | First responder for all SEVs |
| Incident Commander (rotation) | `#incident-response` Slack channel | Assigned on SEV-1 and SEV-2 |
| Security Team Lead | `security@example.com` | All SEV-1 and SEV-2 incidents |
| Registry Operator | `infra@example.com` | Registry containment actions |
| Infrastructure Lead | `infra@example.com` | Network blocks, firewall changes |
| Engineering Director | Direct contact | SEV-1 with production impact |
| CISO / VP Security | Direct contact | SEV-1 with data breach potential |
| Legal / Compliance | `legal@example.com` | Data breach, regulatory notification requirements |
| Communications / PR | `comms@example.com` | Customer-facing impact |

### Escalation Matrix

```
SEV-4 (Low)     -> On-call Engineer
SEV-3 (Medium)  -> On-call Engineer + Security Analyst
SEV-2 (High)    -> Incident Commander + Security Team Lead + Registry Operator
SEV-1 (Critical) -> All of the above + Infrastructure Lead + Engineering Director
                    + CISO if data breach potential
                    + Legal if regulatory notification required
```

### External Resources

- [GitLab Security Incident Response](https://about.gitlab.com/security/)
- [PyPI Security Reporting](https://pypi.org/security/)
- [npm Security Reporting](https://docs.npmjs.com/reporting-malware-in-an-npm-package)
- [Docker Hub Security](https://docs.docker.com/docker-hub/)
- [CISA Incident Reporting](https://www.cisa.gov/report)
- [NIST SP 800-61r2: Computer Security Incident Handling Guide](https://csrc.nist.gov/publications/detail/sp/800-61/rev-2/final)
- [OpenSSF Package Analysis](https://github.com/ossf/package-analysis)
- [OSV.dev (Open Source Vulnerability Database)](https://osv.dev/)
