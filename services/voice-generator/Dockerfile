ARG CUDA_VERSION=12.4.0
ARG UBUNTU_VERSION=22.04
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3-pip \
    ca-certificates \
    git \
    libopus-dev \
    build-essential \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && python3 -m pip install --upgrade pip setuptools wheel

WORKDIR /app

RUN git clone https://github.com/NVIDIA/personaplex.git /tmp/personaplex && \
    python3 -m pip install --no-cache-dir /tmp/personaplex/moshi/. && \
    python3 -c "import moshi; print('Moshi installed successfully')" && \
    rm -rf /tmp/personaplex

COPY requirements.txt .
RUN python3 -m pip install --no-cache-dir -r requirements.txt

RUN groupadd -r voicegen -g 1000 && \
    useradd -r -u 1000 -g voicegen -m -s /sbin/nologin voicegen

RUN chown -R voicegen:voicegen /app

COPY --chown=voicegen:voicegen generate_voice_prompt.py .

USER voicegen

ENTRYPOINT ["python3", "generate_voice_prompt.py"]
