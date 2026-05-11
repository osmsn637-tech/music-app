FROM python:3.12-slim

# Mutagen is a small pure-Python tag library; no system deps needed.
RUN pip install --no-cache-dir mutagen==1.47.0

WORKDIR /app
COPY import.py /app/import.py

ENTRYPOINT ["python", "/app/import.py"]
