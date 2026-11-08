ARG TARGET
FROM docker.io/library/eclipse-temurin:25.0.1_8-jdk AS build-temurin
WORKDIR /build
COPY java/VirtualDispatch.java .
RUN javac --release 25 VirtualDispatch.java

FROM ghcr.io/graalvm/jdk-community:25.0.1 AS build-graal-jit
WORKDIR /build
COPY java/VirtualDispatch.java .
RUN javac --release 25 VirtualDispatch.java

FROM ghcr.io/graalvm/native-image-community:25.0.1 AS build-graal-native
WORKDIR /build
COPY java/VirtualDispatch.java .
RUN javac --release 25 VirtualDispatch.java && native-image --no-fallback -O3 VirtualDispatch virtual-dispatch

FROM docker.io/library/eclipse-temurin:25.0.1_8-jre AS final-temurin-c2
WORKDIR /benchmark
COPY --from=build-temurin /build/*.class ./
ENTRYPOINT ["java", "VirtualDispatch"]

FROM ghcr.io/graalvm/jdk-community:25.0.1 AS final-graalvm-jit
WORKDIR /benchmark
COPY --from=build-graal-jit /build/*.class ./
ENTRYPOINT ["java", "VirtualDispatch"]

FROM docker.io/library/debian:bookworm-20251020-slim AS final-graalvm-native
WORKDIR /benchmark
COPY --from=build-graal-native /build/virtual-dispatch ./
ENTRYPOINT ["/benchmark/virtual-dispatch"]

FROM final-${TARGET}
