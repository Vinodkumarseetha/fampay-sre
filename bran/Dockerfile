# ── Stage 1: Build dependencies ───────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Production image ─────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Create non-root user
RUN useradd --no-create-home --shell /bin/false bran && \
    chown -R bran:bran /app

# Copy application source
COPY --chown=bran:bran . .

USER bran

ENV DJANGO_SETTINGS_MODULE=bran.settings \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/bran/health/')"

# Gunicorn: 2-4 workers per CPU core, tune via env
CMD gunicorn bran.wsgi:application \
    --bind "0.0.0.0:${PORT}" \
    --workers "${GUNICORN_WORKERS:-4}" \
    --threads "${GUNICORN_THREADS:-2}" \
    --worker-class gthread \
    --access-logfile - \
    --error-logfile - \
    --log-level "${LOG_LEVEL:-info}" \
    --timeout 30
