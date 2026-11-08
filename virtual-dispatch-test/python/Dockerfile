FROM python:3.14.0-slim-bookworm
ARG TARGET
RUN test "$TARGET" = cpython
WORKDIR /benchmark
COPY python/virtual_dispatch.py /benchmark/virtual_dispatch.py
ENTRYPOINT ["python3", "/benchmark/virtual_dispatch.py"]
