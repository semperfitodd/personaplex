FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN groupadd -r voicegen -g 1000 && \
    useradd -r -u 1000 -g voicegen -m -s /sbin/nologin voicegen && \
    chown -R voicegen:voicegen /app

COPY --chown=voicegen:voicegen generate_voice_prompt.py .

USER voicegen

ENTRYPOINT ["python3", "generate_voice_prompt.py"]
