#!/usr/bin/python3
# -*- coding: utf-8 -*-

def main():
    from Cython.Distutils import build_ext
    from os import chdir
    from pathlib import Path
    from setuptools import Extension, setup
    from sys import hexversion
    from pyximport import get_distutils_extension

    # allow setup.py to be run from any path
    root_path = Path(__file__).parent
    if root_path != Path('.'):
      chdir(str(root_path))

    with open('README.rst') as readme:
        README = readme.read()

    compile_time_env \
        = {'PY_VERSION_HEX': hexversion,
           'PY_MAJOR_VERSION': hexversion >> 24,
           'PY_MINOR_VERSION': (hexversion >> 16) & 0xff,
           'PY_MICRO_VERSION': (hexversion >> 8) & 0xff,
           'PY_RELEASE_LEVEL': (hexversion >> 4) & 0xf,
           'PY_RELEASE_SERIAL': (hexversion >> 0) & 0xf}

    module_path = Path('django_number_place')
    ext_modules = []
    packages = set()
    for path in module_path.rglob('*.pyx'):
        packages.add('.'.join(path.parts[:-1]))
        ext, args = get_distutils_extension(
            '.'.join(path.parts)[:-4],
            str(path),
            (hexversion >> 24))
        setattr(ext, 'cython_compile_time_env', compile_time_env)
        ext_modules.append(ext)
    for path in module_path.rglob('*.py'):
        packages.add('.'.join(path.parts[:-1]))
    setup(
        name='django_number_place',
        version='0.1',
        packages=('django_number_place', 'django_number_place.templatetags'),
        package_data={'django_number_place': ('static/*', 'templates/*.html')},
        license='BSD License',  # example license
        description='A simple Django app to solve Number Place (called Sudoku) stepwise.',
        long_description=README,
        url='https://www.github.com/shun-tucorin/django_number_place',
        author='shun',
        author_email='shun@tucorin.com',
        classifiers=(
            'Environment :: Web Environment',
            'Framework :: Django',
            'Framework :: Django :: 2.2',
            'Intended Audience :: Developers',
            'License :: OSI Approved :: BSD License',
            'Operating System :: OS Independent',
            'Programming Language :: Python',
            'Programming Language :: Python :: 3.5',
            'Programming Language :: Python :: 3.6',
            'Topic :: Internet :: WWW/HTTP',
            'Topic :: Internet :: WWW/HTTP :: Dynamic Content'),
        ext_modules=ext_modules,
        cmdclass={'build_ext': build_ext})


if __name__ == '__main__':
    main()

