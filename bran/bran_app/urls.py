from django.urls import path
from . import views

urlpatterns = [
    path("", views.bran_index, name="bran_index"),
    path("reach-hodor/", views.bran_reach_hodor, name="bran_reach_hodor"),
    path("health/", views.health, name="health"),
    path("ready/", views.ready, name="ready"),
]
