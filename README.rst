============
Number Place
============

Number Place is a simple Django app to solve Number Place (called Sudoku) stepwise.

Detailed documentation is in the "docs" directory.

Quick start
-----------

1. Add "number_place" to your INSTALLED_APPS setting like this::

    INSTALLED_APPS = [
        ...
        'django_number_place.apps.AppConfig',
    ]

2. Include the polls URLconf in your project urls.py like this::

    path('number_place/', include('django_number_place.urls')),

3. Run `python manage.py migrate` to create the number_place's models.

4. Start the development server and visit http://127.0.0.1:8000/admin/
   to create a number_place (you'll need the Admin app enabled).

5. Visit http://127.0.0.1:8000/number_place/ to participate in the number_place.
