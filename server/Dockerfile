# ── Stage 1: vault binary ─────────────────────────────────────────────────────
FROM hashicorp/vault:latest AS source

# ── Stage 2: set up users and directory structure ─────────────────────────────
# Wolfi has a shell — use it to create the vault user and pre-create
# directories with correct ownership. Results are copied to the final image.
FROM cgr.dev/chainguard/wolfi-base:latest AS builder

RUN addgroup -g 1000 vault && \
    adduser  -u 1000 -G vault -s /sbin/nologin -D vault && \
    mkdir -p /vault/data /vault/logs /vault/config /vault/tls && \
    chown -R vault:vault /vault && \
    chmod 750 /vault/data /vault/logs /vault/tls && \
    chmod 755 /vault/config

# ── Stage 3: final minimal image ──────────────────────────────────────────────
# Vault is built with Cgo disabled — fully static binary, no libc needed.
# cgr.dev/chainguard/static: no shell, no package manager, CA certs included,
# near-zero CVE surface.
FROM cgr.dev/chainguard/static:latest

# Vault binary
COPY --from=source  /bin/vault  /bin/vault

# Directory structure with correct ownership from builder stage
COPY --from=builder /vault      /vault

# User and group definitions from builder stage
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group  /etc/group

USER 1000

EXPOSE 8100 8200

# Run vault directly — no entrypoint wrapper, no shell, no surprises
ENTRYPOINT ["/bin/vault"]
CMD ["server", "-config=/vault/config"]
