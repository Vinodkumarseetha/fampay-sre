import os
import socket
import logging
from datetime import datetime

import requests
from django.conf import settings
from django.http import JsonResponse

logger = logging.getLogger(__name__)


def bran_index(request):
    response_data = {
        "service": "bran",
        "message": f"Bran is watching. (env: {settings.APP_ENV})",
        "timestamp": datetime.utcnow().isoformat(),
        "host": socket.gethostname(),
        "version": settings.APP_VERSION,
    }
    logger.info("bran_index called", extra={"path": request.path})
    return JsonResponse(response_data)


def bran_reach_hodor(request):
    """
    Bran CAN reach hodor via internal network.
    This demonstrates the one-directional connectivity.
    """
    hodor_url = settings.HODOR_INTERNAL_URL + "/hodor/"
    try:
        resp = requests.get(hodor_url, timeout=5)
        hodor_data = resp.json()
        logger.info("Successfully reached hodor", extra={"hodor_status": resp.status_code})
        return JsonResponse({
            "service": "bran",
            "message": "Bran successfully reached hodor",
            "hodor_response": hodor_data,
        })
    except requests.exceptions.ConnectionError as e:
        logger.error("Failed to reach hodor", extra={"error": str(e)})
        return JsonResponse(
            {"service": "bran", "error": "Could not reach hodor", "detail": str(e)},
            status=503,
        )
    except Exception as e:
        logger.exception("Unexpected error reaching hodor")
        return JsonResponse({"service": "bran", "error": str(e)}, status=500)


def health(request):
    return JsonResponse({"status": "healthy", "service": "bran"})


def ready(request):
    return JsonResponse({"status": "ready", "service": "bran"})
