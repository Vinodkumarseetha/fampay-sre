from django.urls import path, include

urlpatterns = [
    path("bran/", include("bran_app.urls")),
    path("", include("django_prometheus.urls")),
]
