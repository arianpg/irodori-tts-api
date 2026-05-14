FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev \
    git ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/bin/python

WORKDIR /app

# Install PyTorch with CUDA 12.8 (required for Blackwell / RTX 50xx)
RUN pip install --upgrade pip && \
    pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128

# Install Irodori-TTS: clone and install dependencies manually
# (direct pip install fails due to multiple top-level packages in flat-layout)
RUN git clone --depth 1 https://github.com/Aratako/Irodori-TTS.git /tmp/irodori-tts && \
    pip install -r /tmp/irodori-tts/requirements.txt && \
    cp -r /tmp/irodori-tts/irodori_tts /app/irodori_tts && \
    rm -rf /tmp/irodori-tts

# Install API server dependencies
RUN pip install fastapi "uvicorn[standard]" pydub

COPY server.py .

RUN mkdir -p /voices /model

EXPOSE 8880

CMD ["python", "server.py"]
