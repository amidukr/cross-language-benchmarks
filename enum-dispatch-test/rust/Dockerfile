FROM docker.io/library/rust:1.90.0-bookworm AS build
ARG TARGET
RUN test "$TARGET" = rust
WORKDIR /src
COPY rust/Cargo.toml rust/Cargo.lock ./
COPY rust/src ./src
RUN cargo build --release --locked
FROM build AS assembly
ENV RUSTFLAGS="-C debuginfo=2"
RUN cargo build --release --locked
FROM docker.io/library/debian:bookworm-20251020-slim
COPY --from=build /src/target/release/enum-dispatch /enum-dispatch
ENTRYPOINT ["/enum-dispatch"]
