FROM docker.io/library/python:3.14.0-slim-bookworm AS assembly
ARG TARGET
RUN test "$TARGET" = cpython
WORKDIR /benchmark
COPY --chmod=0444 python/enum_dispatch.py /benchmark/enum_dispatch.py
ENTRYPOINT ["python3", "/benchmark/enum_dispatch.py"]
