# -*- coding: utf-8 -*-

from django.urls import path
from . import views

urlpatterns = [
    path('1.html', views.View1.as_view(), name='1'),
]
