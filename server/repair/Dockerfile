FROM python:3.12-slim

# faster-whisper needs ffmpeg + libsndfile for decoding mp3/m4a/etc.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        requests==2.32.3 \
        faster-whisper==1.2.1

WORKDIR /app
COPY repair.py /app/repair.py

# Force unbuffered output so docker logs show per-song progress in
# real time instead of dumping at exit.
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "-u", "/app/repair.py"]
