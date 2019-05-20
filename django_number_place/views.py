# -*- coding: utf-8 -*-

from django.template.response import TemplateResponse
from django.views.generic import View
from .forms import Form1


def load_module(name):
    from os import path
    from sys import hexversion
    from sysconfig import get_platform, get_python_version
    prefix = path.join(
        path.dirname(__file__),
        'lib.' + get_platform() + '-' + get_python_version(),
        name)
    if hexversion < 0x3040000:
        from imp import C_EXTENSION, get_suffixes, load_dynamic
        if load_dynamic is not None:
            for suffix in get_suffixes():
                if suffix[2] == C_EXTENSION:
                    file = prefix + suffix[0]
                    if path.isfile(file):
                        return load_dynamic(name, file)
    else:
        from importlib import machinery, _bootstrap
        for suffix in machinery.EXTENSION_SUFFIXES:
            file = prefix + suffix
            if path.isfile(file):
                return _bootstrap._load(
                    machinery.ModuleSpec(
                        name=name,
                        loader=machinery.ExtensionFileLoader(name, file),
                        origin=file))
    raise ImportError('No module named ' + name)

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


_views = load_module('_views')

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
