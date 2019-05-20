# -*- coding: utf-8 -*-

from django.template.response import TemplateResponse
from django.views.generic import View
from .forms import Form1
from . import _views

def place_indexes():
    result = []
    # 3x3 blocks
    for row_0 in range(3):
        for col_0 in range(3):
            result.append(
                [(row_0 * 3 + row_1) * 9 + col_0 * 3 + col_1
                 for row_1 in range(3)
                 for col_1 in range(3)])
    # horizontal
    for row_0 in range(9):
        result.append([row_0 * 9 + col_0 for col_0 in range(9)])
    # vertical
    for col_0 in range(9):
        result.append([row_0 * 9 + col_0 for row_0 in range(9)])
    return result


class View1(View):
    def get(self, request, *args, **kwargs):
        data = request.GET
        return TemplateResponse(
            request=request,
            template=('1.html',),
            context={'view': self,
                     'form': Form1(data=data),
                     'answer': _views.get_answer(data, place_indexes())})


    def post(self, request, *args, **kwargs):
        data = request.POST
        return TemplateResponse(
            request=request,
            template=('1.html',),
            context={'view': self,
                     'form': Form1(data=data),
                     'answer': _views.get_answer(data, place_indexes())})

