FROM docker.io/library/python:3.14.0-slim-bookworm AS assembly
ARG TARGET
RUN test "$TARGET" = cpython
WORKDIR /benchmark
COPY --chmod=0444 python/virtual_dispatch.py /benchmark/virtual_dispatch.py
ENTRYPOINT ["python3", "/benchmark/virtual_dispatch.py"]
