ARG TARGET
FROM docker.io/library/gcc:15.2.0-bookworm AS build-c-gcc
RUN apt-get update && apt-get install -y --no-install-recommends cmake=3.25.1-1 ninja-build=1.11.1-2~deb12u1 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY c/main.c c/main.c
COPY cpp/main.cpp cpp/main.cpp
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ && cmake --build build --target enum-dispatch-c
FROM build-c-gcc AS vectorization-c-gcc
RUN cmake -S . -B build-vectorization -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=gcc \
      -DCMAKE_CXX_COMPILER=g++ \
      -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG -fopt-info-vec-all=/src/vectorization.txt" \
    && cmake --build build-vectorization --target enum-dispatch-c
FROM docker.io/silkeh/clang:21-bullseye AS build-c-clang
RUN apt-get update && apt-get install -y --no-install-recommends cmake ninja-build && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY c/main.c c/main.c
COPY cpp/main.cpp cpp/main.cpp
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ && cmake --build build --target enum-dispatch-c
FROM build-c-clang AS vectorization-c-clang
RUN cmake -S . -B build-vectorization -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG -Rpass=loop-vectorize -Rpass-missed=loop-vectorize -Rpass-analysis=loop-vectorize -fsave-optimization-record -foptimization-record-file=/src/vectorization.yaml" \
    && cmake --build build-vectorization --target enum-dispatch-c \
      > /src/vectorization-build.txt 2>&1
FROM docker.io/library/debian:bookworm-20251020-slim AS final-c-gcc
COPY --from=build-c-gcc /src/build/enum-dispatch-c /enum-dispatch
ENTRYPOINT ["/enum-dispatch"]
FROM docker.io/library/debian:bookworm-20251020-slim AS final-c-clang
COPY --from=build-c-clang /src/build/enum-dispatch-c /enum-dispatch
ENTRYPOINT ["/enum-dispatch"]
FROM final-${TARGET}
