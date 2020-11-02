#!/usr/bin/python3
# coding: utf-8

from Cython.Build import cythonize
import csv
from jinja2 import Environment, FileSystemLoader
import os
from pathlib import Path
from setuptools import setup
from setuptools.extension import Extension


def process_setup_dir(jinja2_env, project_path, dir_path):
    forms = {}
    csv_st_atime_ns = 0
    csv_st_mtime_ns = 0
    dir_name = dir_path.name
    for file_path in dir_path.glob('*.csv'):
        stat = file_path.stat()
        if csv_st_atime_ns < stat.st_atime_ns:
            csv_st_atime_ns = stat.st_atime_ns
        if csv_st_mtime_ns < stat.st_mtime_ns:
            csv_st_mtime_ns = stat.st_mtime_ns

        with file_path.open(mode='r', encoding='utf-8', newline='') as fp:
            names = set()
            blocks = []

            for record in csv.reader(fp):
                if len(record) != 9:
                    continue
                blocks.append(tuple(record))
                for i in range(9):
                    names.add(record[i])
            names = list(names)
            names.sort()
            forms[file_path.stem] = {
                'names': names,
                'blocks': blocks,
            }

    # creating source files
    for file_path in dir_path.glob('*.j2'):
        stat = file_path.stat()
        template = jinja2_env.get_template(
            '/'.join([str(p) for p in file_path.parts])
        )
        file_path = project_path.joinpath(
            dir_name,
            file_path.stem
        )
        with file_path.open(mode='w', encoding='utf-8') as fp:
            template.stream({'forms': forms}).dump(fp)
        os.utime(
            file_path,
            ns=(
                max(csv_st_atime_ns, stat.st_atime_ns),
                max(csv_st_mtime_ns, stat.st_mtime_ns),
            )
        )


def main():
    # allow setup.py to be run from any path
    root_path = Path(__file__).parent
    setup_path = root_path.joinpath('setup')
    project_path = root_path.joinpath('django_number_place')
    number_place_path = project_path.joinpath('number_place')

    jinja2_env = Environment(loader=FileSystemLoader(root_path))
    jinja2_env.line_comment_prefix = '##'
    jinja2_env.trim_blocks = False
    jinja2_env.lstrip_blocks = False
    jinja2_env.keep_trailing_newline = True

    # reading csv files
    for dir_path in setup_path.iterdir():
        process_setup_dir(jinja2_env, project_path, dir_path)

    # making from *.pyx to python dynamic library
    ext_modules = []
    for file_path in project_path.glob('**/*.pyx'):
        path_parts = [
            str(p) for p in file_path.parent.relative_to(root_path).parts
        ]
        path_parts.append(file_path.stem)
        ext_modules.append(
            Extension('.'.join(path_parts), [str(file_path)])
        )

    file_path = root_path.joinpath('README.rst')
    with file_path.open(mode='r', encoding='utf-8') as fp:
        README = fp.read()

    number_place_data_files = []
    for name in ('static', 'jinja2'):
        for file_path in number_place_path.joinpath(name).glob('**/*'):
            number_place_data_files.append(
                str(file_path.relative_to(number_place_path))
            )

    setup(
        name='django_number_place',
        version='0.5',
        packages=[
            'django_number_place',
            'django_number_place.number_place',
            'django_number_place.project',
        ],
        package_data={
            'django_number_place.number_place': number_place_data_files,
        },
        license='BSD License',
        description='Simple Django app to solve Number Place'
                    ' (called Sudoku) in stages.',
        long_description=README,
        url='https://www.github.com/shun-tucorin/django_number_place',
        author='shun',
        author_email='shun@tucorin.com',
        classifiers=[
            'Environment :: Web Environment',
            'Framework :: Django',
            'Framework :: Django :: 3.0',
            'Framework :: Django :: 3.1',
            'Intended Audience :: Developers',
            'License :: OSI Approved :: BSD License',
            'Operating System :: OS Independent',
            'Programming Language :: Python :: 3.6',
            'Programming Language :: Python :: 3.7',
            'Programming Language :: Python :: 3.8',
            'Topic :: Internet :: WWW/HTTP',
            'Topic :: Internet :: WWW/HTTP :: Dynamic Content',
        ],
        ext_modules=cythonize(ext_modules),
        py_modules=[
            'django_number_place'
        ],
        zip_safe=False,
    )


if __name__ == '__main__':
    main()
