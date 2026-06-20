FROM python:3.12-slim

# faster-whisper needs ffmpeg + libsndfile for decoding mp3/m4a/etc.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        requests==2.32.3 \
        faster-whisper==1.2.1 \
        demucs==4.0.1 \
        torch==2.5.1 \
        torchaudio==2.5.1 \
        soundfile==0.12.1 \
        whisperx==3.4.2 \
        pyannote.audio==3.3.2 \
        "audio-separator[cpu]==0.44.2"
# demucs is what makes rap transcription usable — it splits the song into
# stems (vocals/drums/bass/other) so Whisper sees the vocal stem with the
# 808s and ad-libs muted. Adds ~1.5GB to the image (torch + soundfile
# stack) but is opt-in via the transcribe pass. soundfile is required as
# the torchaudio backend for writing the vocals.wav stem — without it
# demucs runs separation successfully then crashes at save.
#
# audio-separator runs the Mel-Band RoFormer vocal model that _isolate_vocals()
# now prefers over demucs (cleaner vocals → tighter word alignment); demucs
# stays as the automatic fallback. The [cpu] extra pulls onnxruntime-cpu and
# the RoFormer .ckpt runs on the torch pinned above. First align/transcribe run
# downloads the model (~hundreds of MB) into the audio-separator cache. If pip
# can't reconcile these pins on rebuild, relax the audio-separator pin — its
# numpy/torch range is the most likely point of friction.

WORKDIR /app
COPY repair.py /app/repair.py

# Force unbuffered output so docker logs show per-song progress in
# real time instead of dumping at exit.
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "-u", "/app/repair.py"]
