ARG TARGET
FROM docker.io/library/gcc:15.2.0-bookworm AS build-cpp-gcc
RUN apt-get update && apt-get install -y --no-install-recommends cmake=3.25.1-1 ninja-build=1.11.1-2~deb12u1 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY c/main.c c/main.c
COPY cpp/main.cpp cpp/main.cpp
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ && cmake --build build --target enum-dispatch-cpp
FROM build-cpp-gcc AS vectorization-cpp-gcc
RUN cmake -S . -B build-vectorization -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=gcc \
      -DCMAKE_CXX_COMPILER=g++ \
      -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -fopt-info-vec-all=/src/vectorization.txt" \
    && cmake --build build-vectorization --target enum-dispatch-cpp
FROM docker.io/silkeh/clang:21-bullseye AS build-cpp-clang
RUN apt-get update && apt-get install -y --no-install-recommends cmake ninja-build && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY c/main.c c/main.c
COPY cpp/main.cpp cpp/main.cpp
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ && cmake --build build --target enum-dispatch-cpp
FROM build-cpp-clang AS vectorization-cpp-clang
RUN cmake -S . -B build-vectorization -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -Rpass=loop-vectorize -Rpass-missed=loop-vectorize -Rpass-analysis=loop-vectorize -fsave-optimization-record -foptimization-record-file=/src/vectorization.yaml" \
    && cmake --build build-vectorization --target enum-dispatch-cpp \
      > /src/vectorization-build.txt 2>&1
FROM docker.io/library/gcc:15.2.0-bookworm AS final-cpp-gcc
COPY --from=build-cpp-gcc /src/build/enum-dispatch-cpp /enum-dispatch
ENTRYPOINT ["/enum-dispatch"]
FROM docker.io/library/debian:bookworm-20251020-slim AS final-cpp-clang
COPY --from=build-cpp-clang /src/build/enum-dispatch-cpp /enum-dispatch
ENTRYPOINT ["/enum-dispatch"]
FROM final-${TARGET}
