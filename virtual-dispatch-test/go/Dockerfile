FROM golang:1.25.3-bookworm AS build
ARG TARGET
RUN test "$TARGET" = go
WORKDIR /src
COPY go/go.mod go/main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /virtual-dispatch .
FROM debian:bookworm-20251020-slim
COPY --from=build /virtual-dispatch /virtual-dispatch
ENTRYPOINT ["/virtual-dispatch"]
