"""
Django settings for bran service.
Reads all config from environment variables (12-factor app).
"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# ── Security ──────────────────────────────────────────────────────────────────
SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]
DEBUG = os.getenv("DEBUG", "False") == "True"
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "*").split(",")

# ── Application definition ────────────────────────────────────────────────────
INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "bran_app",
    "django_prometheus",
]

MIDDLEWARE = [
    "django_prometheus.middleware.PrometheusBeforeMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django_prometheus.middleware.PrometheusAfterMiddleware",
]

ROOT_URLCONF = "bran.urls"

WSGI_APPLICATION = "bran.wsgi.application"

# ── Database ──────────────────────────────────────────────────────────────────
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

# ── Internationalization ──────────────────────────────────────────────────────
LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_TZ = True

# ── Logging ───────────────────────────────────────────────────────────────────
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "()": "pythonjsonlogger.jsonlogger.JsonFormatter",
            "format": "%(asctime)s %(name)s %(levelname)s %(message)s",
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json",
        }
    },
    "root": {
        "handlers": ["console"],
        "level": os.getenv("LOG_LEVEL", "INFO"),
    },
}

# ── Hodor internal URL ─────────────────────────────────────────────────────────
# Bran can reach hodor via internal service name; hodor cannot reach bran
HODOR_INTERNAL_URL = os.getenv("HODOR_INTERNAL_URL", "http://hodor-service:8080")

# ── App config ────────────────────────────────────────────────────────────────
APP_ENV = os.getenv("APP_ENV", "production")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
