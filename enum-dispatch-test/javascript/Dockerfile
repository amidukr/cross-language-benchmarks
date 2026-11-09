FROM docker.io/library/node:26.0.0-bookworm-slim AS assembly
ARG TARGET
RUN test "$TARGET" = node-v8
WORKDIR /benchmark
COPY --chmod=0444 javascript/enum-dispatch.js /benchmark/enum-dispatch.js
ENTRYPOINT ["node", "/benchmark/enum-dispatch.js"]
