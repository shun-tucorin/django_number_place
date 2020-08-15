#!/usr/bin/python3
# coding: utf-8

"""Django's command-line utility for administrative tasks."""


def main():
    import os
    from sys import argv

    os.environ.setdefault(
        'DJANGO_SETTINGS_MODULE',
        'django_number_place.project.settings'
    )
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc
    execute_from_command_line(argv)


if __name__ == '__main__':
    main()
