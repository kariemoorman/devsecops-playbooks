# Secrets Management: Simplified and Secure

A practical guide to keeping your API keys, tokens, passwords, and credentials safe.

---

## Table of Contents

- [Introduction](#introduction)
- [Quick Comparison](#quick-comparison)
- [Encrypted File-Based (Git-friendly)](#encrypted-file-based-git-friendly)
  - [age](#age)
  - [SOPS + age](#sops--age)
  - [git-crypt](#git-crypt)
- [Secrets-as-a-Service (Managed)](#secrets-as-a-service-managed)
  - [Doppler](#doppler)
  - [Infisical](#infisical)
  - [1Password Developer Tools](#1password-developer-tools)
- [Self-Hosted Vaults](#self-hosted-vaults)
  - [HashiCorp Vault](#hashicorp-vault)
  - [OpenBao](#openbao)
- [Cloud-Native](#cloud-native)
  - [AWS Secrets Manager / SSM Parameter Store](#aws-secrets-manager--ssm-parameter-store)
  - [GCP Secret Manager](#gcp-secret-manager)
  - [Azure Key Vault](#azure-key-vault)
- [Best Practices](#general-best-practices)
- [Appendix](#appendix)

---

## Introduction

### Why Secrets Management Matters

Every application has secrets — API keys, database passwords, OAuth tokens, encryption keys. Mismanaging them leads to:

- **Security Breaches**: Leaked credentials are the #1 cause of cloud security incidents. Bots scan GitHub for exposed keys within seconds of a push.
- **Compliance Failures**: SOC 2, HIPAA, and GDPR all require controls around credential storage and access.
- **Team Friction**: Sharing secrets over Slack, email, or sticky notes doesn't scale past one person.
- **AI Agent Risks**: If you're running AI agents that call APIs on your behalf, those agents need credentials too — and they need to be scoped, rotated, and revocable.

### Who This Guide Is For

- Solo developers who want to stop hardcoding secrets in `.env` files committed to git
- Small startup teams (2–10 people) who need to share secrets safely
- Developers building AI agent systems that require programmatic access to credentials
- Anyone who wants a low-cost or free solution that can grow with them


---

## Quick Comparison

| Tool | Category | Cost | Complexity | Best For | Self-Hosted | Key Integrations |
|------|----------|------|------------|----------|-------------|------------------|
| **age** | File encryption | Free | Low | Solo devs, simple encryption | Yes | SOPS, shell scripts |
| **SOPS** | File encryption | Free | Low-Medium | Solo devs to small teams, CI/CD | Yes | age, PGP, AWS KMS, GCP KMS, Azure KV, Vault |
| **git-crypt** | Git encryption | Free | Low | Solo devs, small teams with git | Yes | GPG |
| **Doppler** | Managed SaaS | Free (up to 5 users) | Low | Small teams, fast setup | No | CI/CD, Docker, Kubernetes, Vercel, Netlify |
| **Infisical** | Managed / Self-hosted | Free tier available | Low-Medium | Teams wanting open-source + managed option | Yes | SDKs (Node, Python, Go, etc.), K8s, CI/CD |
| **1Password Dev Tools** | Managed | Free (open-source) / Paid | Low-Medium | Teams already using 1Password | No | CLI (`op`), Connect Server, SDKs |
| **HashiCorp Vault** | Self-hosted vault | Free (BSL) | High | Scaling teams, AI agent credential management | Yes | Everything (AWS, GCP, Azure, K8s, databases) |
| **OpenBao** | Self-hosted vault | Free (OSS) | High | Teams wanting Vault without BSL license | Yes | Vault-compatible APIs |
| **AWS Secrets Manager** | Cloud-native | $0.40/secret/mo | Medium | AWS-native workloads | No | Lambda, ECS, EKS, IAM |
| **AWS SSM Param Store** | Cloud-native | Free (standard) | Medium | AWS-native, cost-sensitive | No | Lambda, ECS, EKS, IAM |
| **GCP Secret Manager** | Cloud-native | Free tier (6 versions, 10k ops, 3 rotations) | Medium | GCP-native workloads | No | Cloud Run, GKE, IAM |
| **Azure Key Vault** | Cloud-native | ~$0.03/10k ops | Medium | Azure-native workloads | No | App Service, AKS, Managed Identity |

---

## Encrypted File-Based (Git-friendly)

### age

#### What It Is

age (pronounced "ah-gay", from the Italian for "to do") is a simple, modern file encryption tool designed as a replacement for PGP. It encrypts files using X25519 keys and has zero configuration.

#### Cost

Free and open source (BSD-3-Clause).

#### Best For

- Solo developers encrypting individual files
- Anyone who wants simple, no-fuss encryption
- Building block for SOPS workflows
- Encrypting secrets for AI agent config files before committing to git

#### How It Works

```
┌──────────┐    age encrypt    ┌──────────────┐
│ .env     │ ───────────────>  │ .env.age     │ ──> safe to commit
│ (plain)  │                   │ (encrypted)  │
└──────────┘    age decrypt    └──────────────┘
             <───────────────
            (needs private key)
```

age uses public-key cryptography. You generate a key pair, encrypt with the public key (the "recipient"), and decrypt with the private key (the "identity").

#### Example

**Install age:**

```bash
# macOS
brew install age

# Linux (Debian/Ubuntu)
sudo apt install age

# From source
go install filippo.io/age/cmd/...@latest
```

**Generate a key pair:**

```bash
age-keygen -o ~/.age/key.txt
```

This outputs something like:

```
# created: 2026-03-25T10:00:00-07:00
# public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
AGE-SECRET-KEY-1QFZPV...
```

Save the public key somewhere accessible. Guard the private key.

**Encrypt a file:**

```bash
# Encrypt .env for one recipient
# -r : recipient (public key that can decrypt the file)
# -o : output file

# Encrypt for multiple recipients
age -r age1abc... -r age1def... -o secrets.env.age secrets.env
```

**Decrypt a file:**

```bash
# -d : decrypt
# -i : identity (private key file)
# -o : output file
age -d -i ~/.age/key.txt -o secrets.env secrets.env.age
```

**Add to `.gitignore`:**

```gitignore
# Plain secrets — never commit
secrets.env
.env
*.key

# Encrypted secrets — safe to commit
!*.age
```

#### Pros / Cons

**Pros:**
- Super simple — one binary, no config files
- Small, auditable codebase
- No key servers or infrastructure needed
- Works anywhere (macOS, Linux, Windows)

**Cons:**
- Encrypts entire files (not individual values)
- No built-in secret rotation or access control
- Manual key distribution for teams
- No audit logging

#### Next Step

Pair age with **SOPS** to encrypt individual values within config files, making diffs readable and merges possible.

---

### SOPS + age

#### What It Is

SOPS (Secrets OPerationS) is a tool for encrypting and decrypting files while keeping the structure (keys, comments) visible. Originally by Mozilla, now maintained at [getsops/sops](https://github.com/getsops/sops). Combined with age as the encryption backend, it's the most practical free secrets solution for teams using git.

#### Cost

Free and open source (MPL-2.0).

#### Best For

- Solo devs to small teams managing config files in git
- CI/CD pipelines that need to decrypt secrets at build time
- Projects that use YAML, JSON, or ENV config formats
- AI agent teams where each agent's config contains scoped API keys
- Teams that want encrypted secrets with readable diffs

#### How It Works

```
┌─────────────────────┐     sops encrypt     ┌──────────────────────────────┐
│ config.yaml         │ ──────────────────>  │ config.yaml (encrypted)      │
│                     │                      │                              │
│ db_host: localhost  │                      │ db_host: localhost           │
│ db_pass: s3cret     │                      │ db_pass: ENC[AES256_GCM,...] │
└─────────────────────┘     sops decrypt     └──────────────────────────────┘
                        <──────────────────
```

SOPS encrypts **values** but leaves **keys** in plaintext. This means:
- Git diffs show which keys changed (not the values)
- Merge conflicts are manageable
- You can see the structure of your config without decrypting

SOPS supports multiple key backends: age, PGP, AWS KMS, GCP KMS, Azure Key Vault, and HashiCorp Vault Transit.

#### Example

**Install SOPS:**

```bash
# macOS
brew install sops

# Linux (from GitHub releases)
# Download the latest binary from https://github.com/getsops/sops/releases
curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64
chmod +x sops-v3.9.4.linux.amd64
sudo mv sops-v3.9.4.linux.amd64 /usr/local/bin/sops
```

**Prerequisite:** Make sure age is installed (see [age section](#age) above).

**Create a `.sops.yaml` configuration file** (put this in your repo root):

```yaml
# .sops.yaml — tells SOPS which keys to use for which files
creation_rules:
  # Encrypt all YAML files in the secrets/ directory
  - path_regex: secrets/.*\.yaml$
    age: >-
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p,
      age1second_recipient_public_key_here

  # Encrypt .env files
  - path_regex: \.env\.encrypted$
    age: >-
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Create a secrets file:**

```yaml
# secrets/app.yaml
database:
  host: db.example.com
  port: 5432
  username: app_user
  password: super_secret_password

api_keys:
  stripe: sk_live_abc123
  openai: sk-proj-xyz789

# Agent-specific credentials
agents:
  researcher:
    api_key: sk-proj-agent-research-key
    max_spend: 10.00
  deployer:
    api_key: sk-proj-agent-deploy-key
    allowed_actions: ["deploy", "rollback"]
```

**Encrypt the file:**

```bash
sops encrypt secrets/app.yaml > secrets/app.enc.yaml

# Or encrypt in-place
sops encrypt -i secrets/app.yaml
```

The encrypted file looks like:

```yaml
database:
    host: ENC[AES256_GCM,data:4kR7lMnF8Q==,iv:...,tag:...,type:str]
    port: ENC[AES256_GCM,data:0aE=,iv:...,tag:...,type:int]
    username: ENC[AES256_GCM,data:8nR9sQ==,iv:...,tag:...,type:str]
    password: ENC[AES256_GCM,data:YWJjMTIz,iv:...,tag:...,type:str]
api_keys:
    stripe: ENC[AES256_GCM,data:...,tag:...,type:str]
    openai: ENC[AES256_GCM,data:...,tag:...,type:str]
agents:
    researcher:
        api_key: ENC[AES256_GCM,data:...,tag:...,type:str]
        max_spend: ENC[AES256_GCM,data:...,tag:...,type:float]
    deployer:
        api_key: ENC[AES256_GCM,data:...,tag:...,type:str]
        allowed_actions: ENC[AES256_GCM,data:...,tag:...,type:list]
sops:
    age:
        - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2026-03-25T17:00:00Z"
    version: 3.9.4
```

**Decrypt the file:**

```bash
# Decrypt to stdout
SOPS_AGE_KEY_FILE=~/.age/key.txt sops decrypt secrets/app.enc.yaml

# Decrypt in-place
SOPS_AGE_KEY_FILE=~/.age/key.txt sops decrypt -i secrets/app.enc.yaml

# Edit encrypted file directly (opens in $EDITOR, re-encrypts on save)
SOPS_AGE_KEY_FILE=~/.age/key.txt sops edit secrets/app.enc.yaml
```

**Use in CI/CD (GitHub Actions example):**

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install sops and age
        run: |
          curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64
          chmod +x sops-v3.9.4.linux.amd64
          sudo mv sops-v3.9.4.linux.amd64 /usr/local/bin/sops
          sudo apt-get install -y age

      - name: Decrypt secrets
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: |
          echo "$SOPS_AGE_KEY" > /tmp/age-key.txt
          SOPS_AGE_KEY_FILE=/tmp/age-key.txt sops decrypt secrets/app.enc.yaml > secrets/app.yaml

      - name: Deploy
        run: ./deploy.sh
```

**Add to `.gitignore`:**

```gitignore
# Plaintext secrets
secrets/app.yaml
.env

# Key files
*.key
~/.age/key.txt

# Encrypted files are SAFE to commit
!secrets/*.enc.yaml
!.sops.yaml
```

#### Pros / Cons

**Pros:**
- Encrypts values, not keys — diffs and structure stay readable
- Supports multiple key backends (age, PGP, AWS KMS, GCP KMS, Azure KV, Vault)
- Multiple recipients — easy team key management
- `sops edit` lets you modify secrets without manual decrypt/encrypt
- Works in any CI/CD system
- Free, no infrastructure required (with age backend)

**Cons:**
- Secrets are still in your git history (encrypted, but still there)
- Key rotation requires re-encrypting all files
- No built-in access control beyond "who has the key"
- No web UI or dashboard
- Team member offboarding means rotating the age key

#### Next Step

When your team grows beyond a handful of people or you need per-environment management, consider **Doppler** or **Infisical** for a managed experience. You can also swap SOPS backends without changing your workflow — add **AWS KMS** for cloud-native key management, or use **HashiCorp Vault / OpenBao** Transit engine for self-hosted encryption key management.

---

### git-crypt

#### What It Is

git-crypt enables transparent encryption and decryption of files in a git repository. Files are encrypted on push and decrypted on pull — if you have the key. It uses AES-256-CTR for encryption and works with GPG keys for team access.

#### Cost

Free and open source (GPL-3.0).

#### Best For

- Solo devs or small teams who want "it just works" encryption in git
- Projects where certain files should be opaque to anyone without access
- Simple setups where you don't need per-value encryption

#### How It Works

```
┌──────────────┐   git add/push   ┌───────────────────────┐
│ secrets.env  │ ───────────────> │ encrypted blob in git │
│ (plaintext   │                  │ (unreadable without   │
│  on disk)    │   git pull       │  the symmetric key)   │
└──────────────┘ <─────────────── └───────────────────────┘
                  (auto-decrypts
                   if you have key)
```

git-crypt uses git's filter and diff mechanisms. You define which files to encrypt via `.gitattributes`. Locally, files appear in plaintext. In the remote repo (and for anyone without the key), they're encrypted binary blobs.

#### Example

**Install git-crypt:**

```bash
# macOS
brew install git-crypt

# Linux (Debian/Ubuntu)
sudo apt install git-crypt

# From source
git clone https://github.com/AGWA/git-crypt.git
cd git-crypt && make && sudo make install
```

**Initialize in your repo:**

```bash
cd your-project
git-crypt init
```

This generates a symmetric key stored in `.git/git-crypt/keys/default`.

**Define which files to encrypt** via `.gitattributes`:

```gitattributes
# Encrypt these file patterns
secrets/** filter=git-crypt diff=git-crypt
*.secret filter=git-crypt diff=git-crypt
.env.production filter=git-crypt diff=git-crypt
```

**Add and commit secrets normally:**

```bash
echo "DATABASE_URL=postgres://user:pass@host/db" > secrets/database.env
git add secrets/database.env .gitattributes
git commit -m "Add encrypted database credentials"
git push
```

The file is plaintext on your disk but encrypted in the remote repository.

**Share access with a teammate (via GPG):**

```bash
# Your teammate generates a GPG key (if they don't have one)
gpg --gen-key

# They export their public key and send it to you
gpg --export --armor teammate@example.com > teammate.gpg

# You import their key and add them
gpg --import teammate.gpg
git-crypt add-gpg-user teammate@example.com
git push
```

**Share access with a symmetric key (simpler, less secure):**

```bash
# Export the symmetric key
git-crypt export-key /path/to/shared-key

# Teammate unlocks the repo with the key
git-crypt unlock /path/to/shared-key
```

**Verify encryption status:**

```bash
# See which files are encrypted
git-crypt status

# Example output:
#     encrypted: secrets/database.env
#     encrypted: .env.production
# not encrypted: README.md
# not encrypted: src/app.js
```

#### Pros / Cons

**Pros:**
- Transparent — no changes to your workflow after setup
- Files are plaintext locally (no manual decrypt step)
- Uses standard GPG keys for team access
- Zero infrastructure, works with any git host

**Cons:**
- Encrypts entire files (not individual values like SOPS)
- Diffs are useless for encrypted files (binary blobs)
- GPG key management can be painful at scale
- Removing team access requires re-keying
- No support for non-GPG key backends (no KMS, no age)
- File must be in `.gitattributes` before first commit — retroactive encryption is tricky

#### Next Step

If you need per-value encryption or multiple key backends, move to **SOPS**. If you're outgrowing file-based approaches entirely, jump to **Doppler** or **Infisical**.

---

## Secrets-as-a-Service (Managed)

### Doppler

#### What It Is

Doppler is a managed secrets platform that centralizes your environment variables and syncs them to wherever your code runs — local dev, CI/CD, staging, production. It replaces `.env` files with a single source of truth.

#### Cost

- **Free tier**: Up to 5 team members, unlimited projects and secrets, community support
- **Team**: $4/seat/month (adds roles, audit logs, integrations)
- **Enterprise**: Custom pricing

#### Best For

- Small teams that want to stop passing `.env` files around
- Projects deploying to multiple platforms (Vercel, Railway, AWS, etc.)
- Teams that want a UI for managing secrets
- Startups that need audit logging for compliance without running infrastructure

#### How It Works

```
┌─────────────┐     Doppler CLI/SDK      ┌────────────┐
│ Developer   │ ──────────────────────>  │  Doppler   │
│ (doppler    │                          │  Cloud     │
│  run -- )   │ <──────────────────────  │            │
│             │   injects env vars       │ ┌────────┐ │
└─────────────┘                          │ │dev     │ │
                                         │ │staging │ │
┌─────────────┐     CI/CD integration    │ │prod    │ │
│ GitHub      │ ──────────────────────>  │ └────────┘ │
│ Actions     │ <──────────────────────  └────────────┘
└─────────────┘   injects at build time
```

Doppler organizes secrets into **projects** and **environments** (dev, staging, prod). You access them via the CLI, SDK, or direct integrations.

#### Example

**Install the Doppler CLI:**

```bash
# macOS
brew install dopplerhq/cli/doppler

# Linux
curl -sLf --retry 3 --tlsv1.2 --proto "=https" \
  'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | \
  sudo gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] \
  https://packages.doppler.com/public/cli/deb/debian any-version main" | \
  sudo tee /etc/apt/sources.list.d/doppler-cli.list
sudo apt update && sudo apt install doppler
```

**Authenticate:**

```bash
doppler login
# Opens browser for authentication
```

**Set up a project:**

```bash
# Create a project (or do it in the Doppler dashboard)
doppler projects create my-app

# Link your local directory to the project
doppler setup
# Select project: my-app
# Select environment: dev
```

**Add secrets (via CLI or dashboard):**

```bash
# Set individual secrets
doppler secrets set DATABASE_URL="postgres://user:pass@host/db"
doppler secrets set STRIPE_KEY="sk_live_abc123"
doppler secrets set OPENAI_API_KEY="sk-proj-xyz789"

# Set multiple at once
doppler secrets set \
  REDIS_URL="redis://localhost:6379" \
  API_SECRET="my_secret_value"
```

**Use secrets in your app:**

```bash
# Run any command with secrets injected as env vars
doppler run -- node server.js
doppler run -- python app.py
doppler run -- ./deploy.sh

# Or fetch as .env format
doppler secrets download --no-file --format env
```

**Use in CI/CD (GitHub Actions):**

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Doppler CLI
        uses: dopplerhq/cli-action@v3

      - name: Deploy with secrets
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
        run: doppler run -- ./deploy.sh
```

**Generate a service token for CI/CD:**

```bash
# Create a read-only token for the production environment
doppler configs tokens create \
  --project my-app \
  --config prd \
  --name "github-actions" \
  --plain
```

#### Pros / Cons

**Pros:**
- Very low friction — `doppler run --` replaces `.env` files entirely
- Web dashboard for non-technical team members
- Built-in environment management (dev/staging/prod)
- Native integrations with Vercel, Netlify, AWS, Docker, Kubernetes
- Audit log on the free tier
- Automatic secret change notifications

**Cons:**
- SaaS only — no self-hosting option
- Vendor lock-in (your secrets live on their infrastructure)
- Free tier limited to 5 users
- Requires internet access to fetch secrets (offline: use `doppler secrets download`)

> **Backup note:** Doppler is a managed service — you don't control the backing storage. Periodically export your secrets (`doppler secrets download --format json`) and store the backup in an encrypted location (e.g., a SOPS-encrypted file or an encrypted S3 bucket). Don't rely solely on a third party to be your only copy.

#### Next Step

If you need self-hosting or open-source control, consider **Infisical**. If you're scaling into infrastructure-heavy workloads, look at **HashiCorp Vault** or your cloud provider's native secrets manager.

---

### Infisical

#### What It Is

Infisical is an open-source secrets management platform. It provides a similar experience to Doppler but can be self-hosted. It offers SDKs, CLI tooling, and a web dashboard for managing secrets across environments.

#### Cost

- **Self-hosted (Community)**: Free, unlimited users and secrets
- **Cloud Free tier**: Up to 5 team members
- **Pro**: $6/user/month
- **Enterprise**: Custom pricing

#### Best For

- Teams that want Doppler-like convenience but need self-hosting
- Open-source-first teams
- Startups that need to manage secrets across multiple services and environments
- Developer managing AI agents that need scoped, rotatable credentials

#### How It Works

```
┌─────────────┐     Infisical CLI/SDK     ┌──────────────┐
│ Developer   │ ───────────────────────>  │  Infisical   │
│ (infisical  │                           │  (Cloud or   │
│  run -- )   │ <───────────────────────  │   self-host) │
│             │   injects env vars        │              │
└─────────────┘                           │ ┌──────────┐ │
                                          │ │Projects  │ │
┌─────────────┐     SDK / API             │ │Envs      │ │
│ Your App    │ ───────────────────────>  │ │Folders   │ │
│ (runtime)   │ <───────────────────────  │ └──────────┘ │
└─────────────┘   fetches secrets         └──────────────┘
```

#### Example

**Self-host with Docker Compose (quickstart):**

```bash
git clone https://github.com/Infisical/infisical.git
cd infisical
cp .env.example .env
docker compose -f docker-compose.prod.yml up -d
```

Access the dashboard at `http://localhost:8080`.

**Or use Infisical Cloud** — sign up at [infisical.com](https://infisical.com).

**Install the CLI:**

```bash
# macOS
brew install infisical/get-cli/infisical

# Linux
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
sudo apt install infisical
```

**Authenticate:**

```bash
infisical login
```

**Initialize a project:**

```bash
cd your-project
infisical init
# Select your organization and project
```

**Add secrets (via CLI or dashboard):**

```bash
# Set secrets for the dev environment
infisical secrets set DATABASE_URL="postgres://user:pass@host/db" --env dev
infisical secrets set STRIPE_KEY="sk_test_abc123" --env dev
```

**Run your app with injected secrets:**

```bash
infisical run --env=dev -- node server.js
infisical run --env=prod -- python app.py
```

**Use the SDK (Node.js example):**

```javascript
import { InfisicalSDK } from "@infisical/sdk";

const client = new InfisicalSDK({
  siteUrl: "https://app.infisical.com", // or your self-hosted URL
});

await client.auth().universalAuth.login({
  clientId: process.env.INFISICAL_CLIENT_ID,
  clientSecret: process.env.INFISICAL_CLIENT_SECRET,
});

const secrets = await client.secrets().listSecrets({
  environment: "prod",
  projectId: "your-project-id",
  secretPath: "/",
});
```

#### Pros / Cons

**Pros:**
- Open-source with self-hosting option (full control)
- SDKs for Node.js, Python, Go, Java, .NET, Ruby
- Web dashboard with secret versioning and audit logs
- Supports secret rotation and dynamic secrets
- Kubernetes operator and CLI for CI/CD
- Agent-friendly: machine identity auth with scoped permissions

**Cons:**
- Self-hosting requires maintaining infrastructure (Postgres, Redis)
- Smaller community compared to Vault or Doppler
- Some advanced features (SCIM, SAML SSO) are enterprise-only
- Cloud free tier limited to 5 users

> **Backup note:** If self-hosting, ensure the backing Postgres database is encrypted at rest and included in your regular backup schedule. If using Infisical Cloud, periodically export secrets via the CLI or API and store backups in an encrypted location.

#### Next Step

If you're scaling into complex infrastructure with dynamic secrets (database credentials, cloud IAM), consider **HashiCorp Vault** or **OpenBao**.

---

### 1Password Developer Tools

#### What It Is

1Password's developer tools let you reference secrets stored in 1Password vaults directly from your code, config files, and CLI. The `op` CLI and Connect Server provide programmatic access to secrets without exporting them to `.env` files.

#### Cost

- **1Password for Open Source**: Free (for qualifying OSS teams)
- **Individual**: $2.99/month
- **Teams**: $3.99/user/month (includes developer tools)
- **Business**: $7.99/user/month

#### Best For

- Teams already using 1Password for password management
- Developers who want one tool for both personal and application secrets
- Small teams that don't want to adopt a separate secrets platform

#### How It Works

```
┌─────────────┐     op CLI / SDK        ┌─────────────┐
│ Developer   │ ─────────────────────>  │  1Password  │
│             │                         │  Vault      │
│ op run --   │ <─────────────────────  │             │
│             │   resolves references   │ ┌─────────┐ │
└─────────────┘                         │ │secrets  │ │
                                        │ │creds    │ │
┌─────────────┐     Connect Server      │ │keys     │ │
│ CI/CD or    │ ─────────────────────>  │ └─────────┘ │
│ Server      │ <─────────────────────  └─────────────┘
└─────────────┘   REST API access
```

The key concept is **secret references** — URIs like `op://vault-name/item-name/field-name` that resolve to actual values at runtime.

#### Example

**Install the `op` CLI:**

```bash
# macOS
brew install 1password-cli

# Linux
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
  https://downloads.1password.com/linux/debian/amd64 stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install 1password-cli
```

**Sign in:**

```bash
eval $(op signin)
```

**Create a vault and add secrets:**

```bash
# Create a vault for your project
op vault create "My App Secrets"

# Add a secret
op item create \
  --category="API Credential" \
  --title="Stripe API Key" \
  --vault="My App Secrets" \
  "credential=sk_live_abc123"

# Add a database credential
op item create \
  --category="Database" \
  --title="Production DB" \
  --vault="My App Secrets" \
  "hostname=db.example.com" \
  "port=5432" \
  "username=app_user" \
  "password=super_secret"
```

**Use secret references in config files:**

Create a `.env` template:

```bash
# .env.template (safe to commit — contains references, not values)
DATABASE_URL=op://My App Secrets/Production DB/url
STRIPE_KEY=op://My App Secrets/Stripe API Key/credential
```

**Inject secrets at runtime:**

```bash
# Run a command with secrets resolved
op run --env-file=.env.template -- node server.js

# Or inject into an existing .env
op inject -i .env.template -o .env
```

**Use in CI/CD with Connect Server:**

For server-to-server access (no human sign-in), deploy a 1Password Connect Server:

```bash
# Create a Connect server and access token in 1Password
# Then use the REST API:
curl -H "Authorization: Bearer $OP_CONNECT_TOKEN" \
  https://your-connect-server:8080/v1/vaults/{vault_id}/items/{item_id}
```

#### Pros / Cons

**Pros:**
- Unified tool — passwords, SSH keys, API tokens, all in one place
- Secret references keep config files committable
- Desktop app integration (biometric unlock)
- Fine-grained access control per vault
- Service accounts for CI/CD without human credentials

**Cons:**
- Not free (unless qualifying OSS project)
- Primarily designed for password management, not infrastructure secrets
- Connect Server needed for headless/server access
- Smaller developer ecosystem compared to Doppler/Infisical
- No self-hosting option for the vault itself

#### Next Step

If you need dynamic secrets, advanced policies, or you're scaling beyond what 1Password's vault model supports, look at **HashiCorp Vault** or cloud-native solutions.

---

## Self-Hosted Vaults

### HashiCorp Vault

#### What It Is

HashiCorp Vault is the industry-standard secrets management tool. It stores, generates, and controls access to secrets with fine-grained policies, audit logging, and support for dynamic secrets (credentials generated on demand). It's far more powerful — and more complex — than the tools above.

#### Cost

- **Community Edition**: Free (BSL 1.1 license — free for most uses, but not for competing products)
- **HCP Vault (managed)**: Starts at ~$0.03/hour for a small cluster
- **Enterprise**: Custom pricing

#### Best For

- Teams with 10+ developers or multiple services
- Organizations needing compliance-grade audit logs
- AI agent orchestration — Vault can issue short-lived, scoped tokens per agent
- Dynamic secrets (auto-generated, auto-revoked database creds, cloud IAM roles)
- Multi-cloud or hybrid environments

#### How It Works

```
┌──────────┐                         ┌──────────────────────┐
│ App /    │   authenticate (token,  │   HashiCorp Vault    │
│ Agent /  │   AppRole, K8s, etc.)   │                      │
│ CI       │ ──────────────────────> │ ┌──────────────────┐ │
│          │                         │ │ Auth Methods     │ │
│          │   read/write secrets    │ │ (Token, AppRole, │ │
│          │ <────────────────────── │ │  K8s, LDAP, etc) │ │
│          │                         │ ├──────────────────┤ │
└──────────┘                         │ │ Secrets Engines  │ │
                                     │ │ (KV, Database,   │ │
┌──────────┐   SOPS encryption key   │ │  Transit, PKI,   │ │
│ SOPS     │ ──────────────────────> │ │  AWS, GCP, etc)  │ │
│          │ <────────────────────── │ ├──────────────────┤ │
└──────────┘   encrypt/decrypt       │ │ Policies (ACL)   │ │
                                     │ │ Audit Log        │ │
                                     │ └──────────────────┘ │
                                     └──────────────────────┘
```

Vault is not just a key-value store. Its secrets engines can:
- **KV**: Store static secrets (like the tools above)
- **Database**: Generate temporary database credentials on demand
- **Transit**: Encrypt/decrypt data without exposing keys (SOPS uses this)
- **PKI**: Issue TLS certificates
- **AWS/GCP/Azure**: Generate cloud IAM credentials on demand

#### Example

**Install Vault:**

```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/vault

# Linux
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```

**Start a dev server (for learning — NOT for production):**

```bash
vault server -dev
```

This starts Vault in-memory on `http://127.0.0.1:8200` and prints a root token.

```bash
# In another terminal
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='hvs.your_root_token_here'
```

**Store and retrieve a secret:**

```bash
# Enable the KV v2 secrets engine (enabled by default in dev mode at secret/)
vault kv put secret/my-app/config \
  database_url="postgres://user:pass@host/db" \
  stripe_key="sk_live_abc123" \
  openai_key="sk-proj-xyz789"

# Read it back
vault kv get secret/my-app/config

# Get a specific field
vault kv get -field=stripe_key secret/my-app/config

# Get as JSON
vault kv get -format=json secret/my-app/config
```

**Set up AppRole auth (for applications and agents):**

AppRole is the standard method for machines/apps/agents to authenticate with Vault.

```bash
# Enable AppRole auth
vault auth enable approle

# Create a policy for your agent
vault policy write agent-researcher - <<EOF
path "secret/data/my-app/agents/researcher/*" {
  capabilities = ["read"]
}
path "secret/data/my-app/shared/*" {
  capabilities = ["read"]
}
EOF

# Create a role tied to the policy
vault write auth/approle/role/researcher-agent \
  token_policies="agent-researcher" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=720h

# Get the role ID and secret ID
vault read auth/approle/role/researcher-agent/role-id
vault write -f auth/approle/role/researcher-agent/secret-id
```

**Authenticate as an agent and read secrets:**

```bash
ROLE_ID="your-role-id"
SECRET_ID="your-secret-id"

# Login
VAULT_TOKEN=$(vault write -field=token auth/approle/login \
  role_id="$ROLE_ID" \
  secret_id="$SECRET_ID")

export VAULT_TOKEN

# Now read secrets (only the paths allowed by the policy)
vault kv get secret/my-app/agents/researcher/api-keys
```

**Use Vault's Transit engine with SOPS:**

```bash
# Enable transit engine
vault secrets enable transit

# Create an encryption key for SOPS
vault write -f transit/keys/sops-key

# Configure SOPS to use Vault Transit
# In .sops.yaml:
# creation_rules:
#   - path_regex: secrets/.*\.yaml$
#     hc_vault_transit_uri: "http://127.0.0.1:8200/v1/transit/keys/sops-key"

sops encrypt secrets/app.yaml
```

**AI Agent Credential Management Pattern:**

```bash
# Store per-agent credentials
vault kv put secret/agents/researcher \
  openai_key="sk-proj-research-key" \
  max_tokens=100000 \
  allowed_models="gpt-4,claude-3"

vault kv put secret/agents/deployer \
  aws_access_key="AKIA..." \
  aws_secret_key="..." \
  allowed_actions="deploy,rollback"

# Each agent gets its own AppRole with a scoped policy
# Tokens are short-lived (1h) and auto-expire
# Audit log tracks which agent accessed what and when
```

#### Pros / Cons

**Pros:**
- Industry standard with massive ecosystem
- Dynamic secrets (database, cloud IAM, PKI)
- Fine-grained ACL policies — perfect for scoping agent access
- Comprehensive audit logging
- SOPS integration via Transit engine
- Auth methods for every platform (K8s, AWS IAM, AppRole, LDAP, OIDC)
- Secret versioning and rotation

**Cons:**
- Operationally complex — unsealing, HA setup, storage backends
- Steep learning curve
- BSL license (not fully open source since August 2023)
- Overkill for solo developers or small teams
- Requires dedicated infrastructure to run in production
- Dev server is easy; production server is a project

> **Backup note:** Vault's storage backend (Consul, Raft, Postgres, etc.) must be encrypted at rest and backed up regularly. Back up the unseal keys and root token separately in a secure, offline location (e.g., Shamir key shares in separate physical safes or a split across trusted team members). Losing unseal keys means losing access to all secrets permanently.

#### Next Step

If the BSL license is a concern, look at **OpenBao**. If you'd rather not self-host, consider your cloud provider's native secrets manager.

---

### OpenBao

#### What It Is

OpenBao is a community-maintained fork of HashiCorp Vault, created in response to Vault's license change from MPL-2.0 to BSL 1.1 in August 2023. It is maintained by the Linux Foundation and aims to provide a fully open-source alternative to Vault with API compatibility.

#### Cost

Free and open source (MPL-2.0).

#### Best For

- Teams that want Vault's capabilities without the BSL license
- Organizations with policies requiring truly open-source software
- Existing Vault users considering migration due to licensing concerns

#### How It Works

OpenBao's architecture is nearly identical to Vault. The CLI, API, and most plugins are compatible. The project forked from Vault 1.14 and is diverging as it develops its own features and removes Vault enterprise tie-ins.

```bash
# OpenBao CLI is similar to Vault's
bao server -dev
export BAO_ADDR='http://127.0.0.1:8200'
bao kv put secret/my-app key=value
bao kv get secret/my-app
```

**Install:**

```bash
# From release binaries
# Check https://github.com/openbao/openbao/releases for the latest version
curl -LO https://github.com/openbao/openbao/releases/download/v2.1.1/bao_2.1.1_linux_amd64.deb
sudo dpkg -i bao_2.1.1_linux_amd64.deb

# Docker
docker run -p 8200:8200 quay.io/openbao/openbao:latest server -dev
```

**Key differences from Vault:**
- CLI binary is `bao` instead of `vault`
- Environment variables use `BAO_` prefix instead of `VAULT_`
- Some enterprise-only Vault features are being implemented in the open
- Active development — check compatibility before migrating a production Vault deployment

#### Pros / Cons

**Pros:**
- Fully open source (MPL-2.0)
- API-compatible with Vault (migration path exists)
- Linux Foundation governance — community-driven
- Free from BSL restrictions

**Cons:**
- Younger project — smaller community and fewer battle-tested deployments
- Not all Vault plugins/integrations are ported yet
- Documentation is still maturing
- Same operational complexity as Vault

> **Backup note:** Same as Vault — encrypt and back up the storage backend regularly, and store unseal keys separately in a secure, offline location. Losing unseal keys means losing access to all secrets permanently.

#### Next Step

If self-hosting isn't for you, look at **cloud-native** secrets managers from AWS, GCP, or Azure: fully managed, pay-as-you-go, and zero operational overhead.

---

## Cloud-Native

These services are tightly integrated with their respective cloud platforms. They're fully managed, require no infrastructure to operate, and scale automatically. Because cloud services change frequently, this section provides overviews and links to official documentation rather than step-by-step examples.

### AWS Secrets Manager / SSM Parameter Store

**AWS Secrets Manager** is a dedicated secrets service with automatic rotation, cross-account sharing, and native integrations with Lambda, ECS, EKS, and RDS.

- **Cost**: $0.40 per secret per month + $0.05 per 10,000 API calls
- **Best for**: Applications running on AWS that need rotation and managed lifecycle
- **Docs**: [https://docs.aws.amazon.com/secretsmanager/](https://docs.aws.amazon.com/secretsmanager/)

**AWS Systems Manager Parameter Store** is a simpler key-value store within SSM. It supports encrypted parameters (SecureString) via AWS KMS.

- **Cost**: Free for standard parameters (up to 10,000, 4KB max each). Advanced parameters cost $0.05/parameter/month.
- **Best for**: Config values and secrets for AWS-native workloads on a budget
- **Docs**: [https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)

**When to use which**: Use Parameter Store for simple secrets and configuration where cost matters. Use Secrets Manager when you need automatic rotation, cross-account access, or managed database credentials.

---

### GCP Secret Manager

Google Cloud Secret Manager stores API keys, passwords, certificates, and other sensitive data with IAM-based access control and audit logging.

- **Cost**: Free tier includes 6 active secret versions, 10,000 access operations, and 3 rotations/month. Beyond that: $0.06/version/location/month for storage, $0.03 per 10,000 access operations, $0.05 per rotation.
- **Best for**: Applications running on GCP (Cloud Run, GKE, Cloud Functions)
- **Docs**: [https://cloud.google.com/secret-manager/docs](https://cloud.google.com/secret-manager/docs)

---

### Azure Key Vault

Azure Key Vault safeguards cryptographic keys, secrets, and certificates. It integrates with Azure services via Managed Identity for passwordless access.

- **Cost**: Standard tier — $0.03 per 10,000 operations for secrets. HSM-backed keys cost more.
- **Best for**: Applications running on Azure (App Service, AKS, Azure Functions)
- **Docs**: [https://learn.microsoft.com/en-us/azure/key-vault/](https://learn.microsoft.com/en-us/azure/key-vault/)

---

## General Best Practices

Regardless of which tool you choose, follow these principles:

### 1. Never Commit Plaintext Secrets

Add secret files to `.gitignore` **before** your first commit. Once a secret is in git history, it's there forever (short of rewriting history).

```gitignore
# Common patterns
.env
.env.*
!.env.example
!.env.template
*.key
*.pem
secrets/
```

### 2. Encrypt Secrets at Rest

Secrets should never sit in plaintext on disk, in databases, or in cloud storage — even in private environments. With the rise of supply chain attacks and AI agent adoption, any unencrypted secret is a target. A compromised dependency, a leaked build artifact, or an agent with over-broad filesystem access can expose plaintext secrets silently.

- Use tools like **SOPS**, **age**, or **git-crypt** to encrypt secrets before they touch disk
- Enable encryption at rest on your databases and cloud storage buckets
- If using a secrets manager (Doppler, Infisical, Vault, OpenBao), ensure the backing storage is encrypted
- For AI agent workflows, never pass plaintext secrets through logs, environment dumps, or unencrypted inter-process communication

### 3. Use a Secret Scanner in Git Hooks & CI

#### Git Hooks

Once a secret hits remote history, remediation is painful. You need to rotate the credential, rewrite git history (or accept the secret lives forever in your repo), and audit for potential exposure. Git hooks helps prevent this scenario by failing the operation before a secret is committed or pushed. Pre-commit and pre-push hooks serve different purposes and catch secrets at different points:

**Pre-Commit**
- Runs on git commit
- Scans only staged files (fast)
- Catches secrets before they enter local history
- Immediate feedback — developer fixes before the commit exists

**Pre-Push**
- Runs on git push
- Can scan commit range being pushed
- Last gate before secrets reach the remote
- Catches anything that slipped past pre-commit (direct commits, amended commits, rebases, --no-verify, Git GUIs that skip hooks)

Both hooks together provide defense in depth: pre-commit blocks secrets from entering local history, pre-push blocks them from reaching the remote.

See [git-secret-scan](https://github.com/kariemoorman/.dotfiles/tree/main/.git-templates) for instructions on how to define and integrate secrets scanning in pre-commit and pre-push hooks using TruffleHog and GitLeaks.


#### CI

CI scanning is your server-side guarantee that every pushed commit gets scanned regardless of local configuration. The goal is to catch accidental commits before they reach your remote. An example GitHub Actions secrets scanning workflow is provided below:

```yaml
name: Secrets Scan

on:
  push:
  pull_request:

jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Scan for secrets
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Popular Secrets Scanners:
- **gitleaks**: [https://github.com/gitleaks/gitleaks](https://github.com/gitleaks/gitleaks)
- **betterleaks**: [https://github.com/betterleaks/betterleaks](https://github.com/betterleaks/betterleaks)
- **truffleHog**: [https://github.com/trufflesecurity/trufflehog](https://github.com/trufflesecurity/trufflehog)

### 4. AuthN/Z Solutions
- Prefer identity (OIDC) over static credentials (PATs)
- If PATs are unavoidable,constrain them aggressively
- When issuing PATs Github, prefer classic PATs over fine-grained PATs, as classic PAT scopes are immutable after creation
- Treat fine-grained PATs as **mutable risk objects**, not static secrets; their permissions can be modified **without changing the token value**

### 5. Rotate Secrets Regularly

- Use dynamic secrets when possible
- Automate secret rotation policies (e.g., automatic expiration, automatic re-issuance per job/run)
- When a team member leaves, rotate every secret they had access to

### 6. Principle of Least Privilege

- Each application, service, or agent should only have access to the secrets it needs
- Use strictly scoped tokens and policies: Restrict tokens to specific repositories/workflows/events to reduce usefulness
- Prefer short-lived tokens over long-lived API keys
- If PATs are required, 

### 7. Separate Secrets by Environment

- Use different keys/tokens for dev, staging, and production
- Never use production credentials in development

### 8. Audit Access

- Enable audit logging wherever possible
- Set up alerts on permission changes
- Enforce re-validation of least privilege assumptions

### 9. Plan for Offboarding

When someone leaves your team:
- Revoke their access tokens immediately
- Rotate any shared secrets they had access to
- Remove their keys from SOPS recipients / git-crypt users
- Review audit logs for unusual access patterns

---

## Appendix

### Glossary

| Term | Definition |
|------|------------|
| **KMS** | Key Management Service — a cloud service that manages encryption keys (AWS KMS, GCP KMS, Azure Key Vault) |
| **Envelope Encryption** | Pattern where data is encrypted with a data key, and the data key is encrypted with a master key (KMS). Used by SOPS. |
| **Transit Engine** | Vault's encryption-as-a-service engine. Encrypts/decrypts data without storing it. |
| **Dynamic Secrets** | Credentials generated on demand with automatic expiration (e.g., Vault generating a short-lived database user) |
| **AppRole** | Vault auth method designed for machines and automated workflows. Uses a role ID + secret ID pair. |
| **Secret Reference** | A URI that points to a secret (e.g., `op://vault/item/field` in 1Password) — resolved at runtime, not stored in config. |
| **HSM** | Hardware Security Module — a physical device that safeguards cryptographic keys. Cloud KMS services often offer HSM-backed keys. |
| **Seal/Unseal** | Vault's security mechanism. A sealed Vault cannot read secrets. Unsealing requires a threshold of key shares. |
| **Machine Identity** | An authentication credential for a non-human entity (application, CI pipeline, AI agent) to access a secrets service. |

### Official Documentation Links

| Tool | Repository / Docs |
|------|------------------|
| age | [https://github.com/FiloSottile/age](https://github.com/FiloSottile/age) |
| SOPS | [https://github.com/getsops/sops](https://github.com/getsops/sops) |
| git-crypt | [https://github.com/AGWA/git-crypt](https://github.com/AGWA/git-crypt) |
| Doppler | [https://docs.doppler.com](https://docs.doppler.com) |
| Infisical | [https://infisical.com/docs](https://infisical.com/docs) |
| 1Password CLI | [https://developer.1password.com/docs/cli](https://developer.1password.com/docs/cli) |
| HashiCorp Vault | [https://developer.hashicorp.com/vault/docs](https://developer.hashicorp.com/vault/docs) |
| OpenBao | [https://github.com/openbao/openbao](https://github.com/openbao/openbao) |
| AWS Secrets Manager | [https://docs.aws.amazon.com/secretsmanager/](https://docs.aws.amazon.com/secretsmanager/) |
| AWS SSM Parameter Store | [https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) |
| GCP Secret Manager | [https://cloud.google.com/secret-manager/docs](https://cloud.google.com/secret-manager/docs) |
| Azure Key Vault | [https://learn.microsoft.com/en-us/azure/key-vault/](https://learn.microsoft.com/en-us/azure/key-vault/) |
| gitleaks | [https://github.com/gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) |
| truffleHog | [https://github.com/trufflesecurity/trufflehog](https://github.com/trufflesecurity/trufflehog) |
