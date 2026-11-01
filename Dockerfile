# --------------------------------------------------
# Common runtime base
# --------------------------------------------------
FROM ubuntu:24.04 AS runtime-base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HUB_CACHE=/data/huggingface \
    TZ=Etc/UTC \
    DATA_DIR=/data \
    LANGUAGE=en \
    DEVICE=NPU \
    ENCODER_BUCKETS=5 \
    ENCODER_LAZY_BUCKETS=20

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    libtbb12 \
    libtbbmalloc2 \
    ocl-icd-libopencl1 \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Hier die bisherigen Level-Zero- und Intel-NPU-Installationen
# aus dem bestehenden Dockerfile übernehmen.


# --------------------------------------------------
# Builder
# --------------------------------------------------
FROM runtime-base AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
COPY scripts ./scripts

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir . \
    && rm -rf /root/.cache/pip


# --------------------------------------------------
# Final runtime
# --------------------------------------------------
FROM runtime-base AS runtime

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/scripts /app/scripts
COPY --from=builder /app/src /app/src

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENV PATH="/opt/venv/bin:$PATH"

# Build-Werkzeuge und Paketmanager aus der Runtime entfernen
RUN rm -rf \
    /opt/venv/lib/python3.12/site-packages/pip \
    /opt/venv/lib/python3.12/site-packages/pip-*.dist-info \
    /opt/venv/lib/python3.12/site-packages/setuptools \
    /opt/venv/lib/python3.12/site-packages/setuptools-*.dist-info \
    /opt/venv/lib/python3.12/site-packages/wheel \
    /opt/venv/bin/pip* \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/data"]
EXPOSE 10300

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 10300)); s.close()" || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
