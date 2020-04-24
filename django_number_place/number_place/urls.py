# coding: utf-8

from django.urls import path
from .views import View1

urlpatterns = (
	path('1.html', View1.as_view(), name='1'),
)
