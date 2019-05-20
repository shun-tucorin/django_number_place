# -*- coding: utf-8 -*-

from django import template

register = template.Library()

@register.filter(name='getpos', is_safe=False)
def do_getpos(value):
    try:
        value = int(value)
        return (((value // 9) % 3) * 3) + (value % 3)
    except:
        return ''
