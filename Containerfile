# Stage 1: Build the Go binary
FROM golang:alpine AS builder

WORKDIR /app

COPY main.go .

RUN CGO_ENABLED=0 GOOS=linux go build -o myapp main.go

FROM alpine:3.22.4

COPY --from=builder /app/myapp /myapp

ENTRYPOINT ["/myapp"]