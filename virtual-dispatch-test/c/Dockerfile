ARG TARGET
FROM gcc:15.2.0-bookworm AS build-c-gcc
RUN apt-get update && apt-get install -y --no-install-recommends cmake=3.25.1-1 ninja-build=1.11.1-2~deb12u1 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY c/main.c c/main.c
COPY cpp/main.cpp cpp/main.cpp
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ && cmake --build build --target virtual-dispatch-c
FROM silkeh/clang:21.1.5-bookworm AS build-c-clang
RUN apt-get update && apt-get install -y --no-install-recommends cmake=3.25.1-1 ninja-build=1.11.1-2~deb12u1 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY c/main.c c/main.c
COPY cpp/main.cpp cpp/main.cpp
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ && cmake --build build --target virtual-dispatch-c
FROM debian:bookworm-20251020-slim AS final-c-gcc
COPY --from=build-c-gcc /src/build/virtual-dispatch-c /virtual-dispatch
ENTRYPOINT ["/virtual-dispatch"]
FROM debian:bookworm-20251020-slim AS final-c-clang
COPY --from=build-c-clang /src/build/virtual-dispatch-c /virtual-dispatch
ENTRYPOINT ["/virtual-dispatch"]
FROM final-${TARGET}
