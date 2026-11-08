FROM docker.io/library/node:26.0.0-bookworm-slim
ARG TARGET
RUN test "$TARGET" = node-v8
WORKDIR /benchmark
COPY javascript/virtual-dispatch.js /benchmark/virtual-dispatch.js
ENTRYPOINT ["node", "/benchmark/virtual-dispatch.js"]
