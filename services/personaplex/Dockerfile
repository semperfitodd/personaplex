ARG CUDA_VERSION=12.1.0
ARG UBUNTU_VERSION=22.04
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    curl \
    ca-certificates \
    git \
    libopus-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone https://github.com/NVIDIA/personaplex.git /tmp/personaplex && \
    pip3 install --no-cache-dir /tmp/personaplex/moshi/. && \
    rm -rf /tmp/personaplex

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

RUN groupadd -r personaplex -g 1000 && \
    useradd -r -u 1000 -g personaplex -m -s /sbin/nologin personaplex

RUN chown -R personaplex:personaplex /app

COPY --chown=personaplex:personaplex . .

USER personaplex

EXPOSE 8998

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f -k https://localhost:8998/ || exit 1

CMD ["python3", "server.py"]
