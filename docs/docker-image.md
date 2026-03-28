# Custom Vault Docker Image

This document explains why we build a custom Vault container image instead of using the official one, how the build works, and what the practical implications are — including why you cannot shell into the container and how we worked around a TLS permission problem.

---

## Why not use the official Vault image?

The official `hashicorp/vault:latest` image is a solid, well-maintained image that is perfectly fine for development and evaluation. HashiCorp publishes it, keeps it updated, and it works out of the box. This is not a criticism of the Vault team or their work — it is a deliberate tradeoff they make to keep the image easy to use.

The tradeoff: the official image is based on Alpine Linux. Alpine is a small Linux distribution — but it is still a full operating system. It contains:

- A shell (`/bin/sh`)
- A package manager (`apk`)
- Standard system utilities (`ls`, `ps`, `curl`, `wget`, `tar`, and many others)
- Shared system libraries
- User management tools
- Hundreds of packages, most of which Vault never touches

All of that makes the image easy to use and debug. You can shell in, install tools, inspect the filesystem. For getting started, that is valuable.

For production, it is a different story. None of that is needed to run Vault. Vault is a single binary. The operating system underneath it is just there to support the binary.

Every package that exists in a container is a potential attack surface. When a CVE is published for Alpine's `libexpat`, `busybox`, or any of the other included packages, your Vault container is technically affected — even though Vault never uses those packages. For a tool whose entire purpose is to protect secrets, carrying that extra surface is an unnecessary risk.

This is not unique to HashiCorp. Most software projects package their tools in a general-purpose Linux image because it is simpler and easier for users. It is a reasonable choice for most applications. A secrets manager is one of the few cases where the extra effort of a minimal image is clearly worth it.

The custom image eliminates this entirely. The final container contains:

- The Vault binary
- The directory structure Vault needs (`/vault/data`, `/vault/logs`, `/vault/config`, `/vault/tls`)
- CA certificates (needed for Vault to make TLS connections to other services)
- User and group definitions for the `vault` user

Nothing else. No shell, no package manager, no utilities, no shared libraries, no operating system.

---

## What is a static binary?

Most programs on Linux depend on shared system libraries — code that is installed separately on the operating system and loaded at runtime. For example, a typical web server might depend on `libc` (the standard C library), `libssl` (for TLS), and others. If those libraries are not present on the system, the program will not start.

This is why you normally cannot take a program compiled on one Linux machine and just copy it to another — the other machine might have different libraries, or none at all.

Vault is compiled differently. HashiCorp builds Vault with all of its dependencies embedded inside the binary itself. There are no external libraries to load. The binary carries everything it needs. This is called a **static binary**.

A static binary can run anywhere — including in a container that has no operating system at all. It does not need libc, libssl, or any other shared library. It just runs.

This is the technical property that makes the minimal image possible. Without it, we would need to install libraries in the container, which means we would need a package manager, which means we would need a shell — and the whole point of the minimal image is to have none of that.

---

## How the image is built — three stages

Docker supports multi-stage builds, which means a single `Dockerfile` can run several build phases and copy results between them. Only the final phase becomes the container image that you actually run. The earlier stages are used purely as build tools and are discarded.

Our `server/Dockerfile` has three stages.

### Stage 1 — Get the Vault binary

```dockerfile
FROM hashicorp/vault:latest AS source
```

We pull the official HashiCorp Vault image. We do not run it and we do not use it as a base. We use it only as a source to extract the Vault binary from. The binary lives at `/bin/vault` inside that image.

Think of this as: "download the official installer, take the executable out of it, throw the rest away."

### Stage 2 — Build the directory structure

```dockerfile
FROM cgr.dev/chainguard/wolfi-base:latest AS builder
```

We use a minimal but shell-capable base image (Wolfi, explained below) to do the setup work that requires a shell:

- Create the `vault` group (GID 1000) and `vault` user (UID 1000)
- Create the directory tree: `/vault/data`, `/vault/logs`, `/vault/config`, `/vault/tls`
- Set ownership of all those directories to the `vault` user
- Set appropriate permissions on each directory

Commands like `addgroup`, `adduser`, `mkdir`, `chown`, and `chmod` all require a shell to run. This is the only stage where we need one. The shell exists here only to do this setup work — it never ends up in the final image.

### Stage 3 — Assemble the final image

```dockerfile
FROM cgr.dev/chainguard/static:latest
```

The final image starts from `cgr.dev/chainguard/static` — a base image that contains essentially nothing (explained in the next section). Into it we copy:

- `/bin/vault` from Stage 1 — the Vault binary
- `/vault` from Stage 2 — the pre-built directory tree with correct ownership already set
- `/etc/passwd` and `/etc/group` from Stage 2 — so the container knows who UID 1000 is

The container is then configured to run as user 1000 (the `vault` user) and to start Vault directly on launch — no shell, no entrypoint script, no wrapper. Just Vault.

---

## What is cgr.dev/chainguard/static?

Chainguard is a company that specialises in minimal, security-focused container base images. Their images are designed to contain as little as possible — only what is genuinely required to run the software.

The `static` image is their base for running static binaries. It contains:

- A valid filesystem layout (the container infrastructure expects certain directories to exist)
- CA certificates — the same bundle of trusted root certificates that browsers use, needed for any software that makes HTTPS connections

That is all. No shell. No package manager. No utilities. No shared libraries. The image is measured in kilobytes rather than megabytes.

Chainguard images are continuously rebuilt against current package versions and regularly scanned for known CVEs (Common Vulnerabilities and Exposures). The attack surface — the amount of code that could potentially contain a vulnerability — is as small as it can possibly be.

The `wolfi-base` image used in Stage 2 is also from Chainguard. Wolfi is Chainguard's Linux distribution, designed for container use. It has a shell and package manager (needed for the setup work in Stage 2), but it is still significantly more minimal and better maintained than Alpine.

---

## What "no shell" means in practice

This is the part that catches most people by surprise the first time they need to troubleshoot Vault.

There is no shell in the final container image. Not `/bin/bash`, not `/bin/sh`, not `/bin/ash`. Nothing.

This means:

```bash
docker exec vault bash    # Error: no such file or directory
docker exec vault sh      # Error: no such file or directory
```

Neither of those commands will work. There is no shell to launch.

**This is intentional.** If an attacker manages to exploit a vulnerability in Vault itself and gain code execution inside the container, there are no tools available to them. No shell to run commands in, no package manager to install tools with, no utilities to explore the filesystem or network with. The container is a dead end.

### Debugging from the outside

Because you cannot get a shell inside the container, all debugging happens from the host machine using Docker commands:

```bash
docker logs vault              # View Vault's output — most problems are visible here
docker logs vault --tail 50    # Last 50 lines
docker inspect vault           # Full container configuration, environment variables, mounts
docker stats vault             # Live CPU and memory usage
```

These commands give you everything you normally need. Vault logs its startup configuration, any errors, and all audit events (if audit logging is configured).

### Running Vault commands

The one thing that does work inside the container is the Vault binary itself:

```bash
docker exec vault vault status
docker exec vault vault secrets list
docker exec vault vault read pki/config/acme
```

The pattern is `docker exec vault vault <command>` — the first `vault` is the container name, the second is the binary path. You also need to pass the right address and token as environment variables, which makes the full command unwieldy.

This is why `server/vault.sh` exists. It wraps the `docker exec` pattern, reads the root token automatically from `init/vault-init.json`, and handles the environment variables for you:

```bash
./server/vault.sh status
./server/vault.sh secrets list
./server/vault.sh read pki/config/acme
```

Internally, `vault.sh` runs:

```bash
docker exec \
  -e VAULT_ADDR=http://127.0.0.1:8100 \
  -e VAULT_TOKEN="$VAULT_TOKEN" \
  vault vault "$@"
```

Use `vault.sh` for all routine Vault administration.

---

## Running as a non-root user and why permissions matter

By default, processes inside Docker containers run as `root` (UID 0). This is convenient but a security problem — if an attacker exploits a vulnerability and gains code execution inside the container, they have root. On a well-configured system, root inside a container is constrained by namespaces and cgroups, but it is still more privilege than necessary.

The recommended practice is to run containers as a non-privileged user. This image runs Vault as UID 1000, a standard unprivileged user ID. This is not a workaround — it is a deliberate security choice.

**Why UID 1000 specifically?**

UID 1000 is conventionally the first regular (non-system) user on a Linux system. Using it signals intent: this is an ordinary unprivileged user, not a system account and not root. It is a widely recognised convention in container security.

**The permission consequence**

Switching to a non-root user immediately creates a file permission challenge. Docker builds run as root by default, so any files created during a build — or files mounted from the host at runtime — are typically owned by root with permissions like 600 (owner read-only). A process running as UID 1000 cannot read them.

In our case, the TLS private key (`server/tls/vault.key`) is generated on the host and mounted into the container. If it is created with mode 600 owned by root, Vault cannot read it and will not start:

```
Error initializing listener of type tcp: error loading X509 key pair:
open /vault/tls/vault.key: permission denied
```

This affects everyone running Vault as a non-root user — not just Windows users, not just WSL users. It is a standard Linux permission problem that comes with the correct decision to not run as root.

**The fix has two parts:**

First, `tls/bootstrap.sh` explicitly sets the key file to mode 644 after generating it:

```bash
chmod 644 "${SCRIPT_DIR}/vault.key"   # readable by uid 1000
```

Mode 644 means the owner can read and write, and all other users can read. This is acceptable for the bootstrap TLS key — it is a self-signed certificate used only for initial setup. Production TLS certificates managed by CertMgr are handled separately.

Second, the builder stage in the Dockerfile sets ownership of the entire `/vault` directory tree to UID 1000 before the final image is assembled:

```dockerfile
RUN addgroup -g 1000 vault && \
    adduser  -u 1000 -G vault -s /sbin/nologin -D vault && \
    mkdir -p /vault/data /vault/logs /vault/config /vault/tls && \
    chown -R vault:vault /vault && \
    chmod 750 /vault/data /vault/logs /vault/tls && \
    chmod 755 /vault/config
```

Because this ownership is baked into the image in Stage 2 and copied into Stage 3, the directories inside the container are always owned by UID 1000 — regardless of what the host OS thinks about ownership. Vault starts as UID 1000 and owns everything it needs to own.

---

## Quick reference — what you can and cannot do

| Operation | Command | Works? |
|-----------|---------|--------|
| Check Vault status | `./server/vault.sh status` | Yes |
| Run any Vault command | `./server/vault.sh <command>` | Yes |
| View logs | `docker logs vault` | Yes |
| View last N lines of logs | `docker logs vault --tail 50` | Yes |
| Inspect config and environment | `docker inspect vault` | Yes |
| Live resource usage | `docker stats vault` | Yes |
| Shell into container | `docker exec vault bash` | No — no shell |
| Shell into container | `docker exec vault sh` | No — no shell |
| Install debug tools | `docker exec vault apk add ...` | No — no package manager |
| Copy files in/out | `docker cp` | Yes — works without a shell |
