# syntax=docker/dockerfile:1
ARG APP
ARG TARGET
ARG COLLECTOR=default

FROM docker.io/library/maven:3.9.16-eclipse-temurin-25 AS jvm-build
WORKDIR /src
COPY .mvn/ .mvn/
COPY console/ console/
COPY swing/ swing/
COPY spring-boot/ spring-boot/
COPY quarkus/ quarkus/
RUN mkdir -p /build/console /build/swing && \
    javac --release 25 -d /build/console console/src/ConsoleHello.java && \
    javac --release 25 -d /build/swing swing/src/SwingHello.java && \
    mvn -f spring-boot/pom.xml -DskipTests package && \
    mkdir -p /build/spring-boot && \
    cp spring-boot/target/spring-hello-1.0.0.jar /build/spring-boot/app.jar && \
    mvn -f quarkus/pom.xml -DskipTests package && \
    mkdir -p /build/quarkus && \
    cp -a quarkus/target/quarkus-app/. /build/quarkus/

FROM ghcr.io/graalvm/native-image-community:25.0.1 AS native-build
ARG APP
ARG COLLECTOR
WORKDIR /src
COPY --from=jvm-build /usr/share/maven /usr/share/maven
ENV PATH="/usr/share/maven/bin:${PATH}"
COPY .mvn/ .mvn/
COPY console/ console/
COPY swing/ swing/
COPY spring-boot/ spring-boot/
COPY quarkus/ quarkus/
RUN set -eux; \
    case "$COLLECTOR" in default) gc=serial ;; serial|epsilon) gc="$COLLECTOR" ;; g1|G1) gc=G1 ;; *) exit 2 ;; esac; \
    mkdir -p /build; \
    native-image --version > /build/toolchain-version.txt 2>&1; \
    case "$APP" in \
      console) \
        javac --release 25 -d /build/classes console/src/ConsoleHello.java; \
        native-image --no-fallback -O3 "--gc=$gc" -cp /build/classes ConsoleHello /build/app ;; \
      swing) \
        javac --release 25 -d /build/classes swing/src/SwingHello.java; \
        native-image --no-fallback -O3 "--gc=$gc" -cp /build/classes SwingHello /build/app ;; \
      spring-boot) \
        mvn -f spring-boot/pom.xml -Pnative -DskipTests "-Dnative.gc=$gc" package; \
        cp spring-boot/target/spring-hello /build/app ;; \
      quarkus) \
        mvn -f quarkus/pom.xml -Pnative -DskipTests \
          "-Dquarkus.native.additional-build-args=--gc=$gc" package; \
        cp quarkus/target/quarkus-hello-1.0.0-runner /build/app ;; \
      *) echo "unsupported application: $APP" >&2; exit 2 ;; \
    esac; \
    chmod 0755 /build/app

FROM docker.io/library/eclipse-temurin:25.0.1_8-jdk AS runtime-temurin-c2
USER root
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash curl procps xvfb xauth && \
    rm -rf /var/lib/apt/lists/*
COPY --from=jvm-build /build /opt/apps
ENV EXECUTION_KIND=jvm

FROM ghcr.io/graalvm/jdk-community:25.0.1 AS runtime-graalvm-jit
USER root
RUN microdnf install -y bash curl procps-ng xorg-x11-server-Xvfb xorg-x11-xauth && \
    microdnf clean all
COPY --from=jvm-build /build /opt/apps
ENV EXECUTION_KIND=jvm

FROM docker.io/library/debian:bookworm-20251020-slim AS runtime-graalvm-native
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash ca-certificates curl procps xvfb xauth && \
    rm -rf /var/lib/apt/lists/*
COPY --from=native-build /build/app /opt/apps/app
COPY --from=native-build /build/toolchain-version.txt /opt/native-build-toolchain-version.txt
ENV EXECUTION_KIND=native

FROM runtime-${TARGET} AS final
ARG APP
ARG TARGET
ARG COLLECTOR
ENV MEMORY_APP=${APP} MEMORY_TARGET=${TARGET} MEMORY_BUILD_COLLECTOR=${COLLECTOR}
WORKDIR /opt/memory-test
COPY scripts/container-launch.sh scripts/container-run-trial.sh ./
RUN chmod 0755 container-launch.sh container-run-trial.sh && \
    { command -v java >/dev/null 2>&1 && java -version 2>&1 || true; } > /opt/toolchain-version.txt && \
    { test ! -s /opt/native-build-toolchain-version.txt || cp /opt/native-build-toolchain-version.txt /opt/toolchain-version.txt; } 2>/dev/null || true && \
    { command -v Xvfb >/dev/null 2>&1 && Xvfb -version 2>&1 || true; } > /opt/xvfb-version.txt && \
    { command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W || true; } > /opt/os-packages.txt && \
    { command -v rpm >/dev/null 2>&1 && rpm -qa || true; } >> /opt/os-packages.txt
ENTRYPOINT ["/opt/memory-test/container-run-trial.sh"]
