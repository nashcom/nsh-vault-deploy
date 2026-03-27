FROM cgr.dev/chainguard/wolfi-base:latest AS builder

RUN apk add --no-cache go

WORKDIR /build
COPY main.go .
COPY go.mod .

RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o vault-fetcher .

# ── runtime ───────────────────────────────────────────────────────────────────

FROM cgr.dev/chainguard/static:latest

COPY --from=builder /build/vault-fetcher /bin/vault-fetcher

ENTRYPOINT ["/bin/vault-fetcher"]
