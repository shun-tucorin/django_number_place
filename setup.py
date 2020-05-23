#!/usr/bin/python3
# -*- coding: utf-8 -*-


def main():
	from Cython.Build import cythonize
	import csv
	from jinja2 import Environment, FileSystemLoader
	import os
	from pathlib import Path, PurePath
	from setuptools import setup
	from setuptools.extension import Extension

	# allow setup.py to be run from any path
	root_path = Path(__file__).parent
	setup_path = root_path.joinpath('setup')
	project_path = root_path.joinpath('django_number_place')
	number_place_path = project_path.joinpath('number_place')

	jinja2_env = Environment(loader=FileSystemLoader(root_path))

	# reading csv files
	for dir_path in setup_path.iterdir():
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
				print(template.render({'forms': forms}), file=fp)
			os.utime(
				file_path,
				ns=(
					max(csv_st_atime_ns, stat.st_atime_ns),
					max(csv_st_mtime_ns, stat.st_mtime_ns),
				)
			)

	# making from *.pyx to python dynamic library
	ext_modules = []
	for file_path in project_path.glob('**/*.pyx'):
		ext_modules.append(
			Extension(
				'.'.join([str(p) for p in file_path.parent.relative_to(root_path).parts])
					+ '.'
					+ file_path.stem,
				[str(file_path)]
			)
		)

	with root_path.joinpath('README.rst').open(mode='r', encoding='utf-8') as fp:
		README = fp.read()

	number_place_data_files = []
	for name in ('static', 'templates'):
		for file_path in number_place_path.joinpath(name).glob('**/*'):
			number_place_data_files.append(
				str(file_path.relative_to(number_place_path))
			)

	setup(
		name='django_number_place',
		version='0.2',
		packages=[
			'django_number_place',
			'django_number_place.number_place',
			'django_number_place.project',
		],
		package_data={
			'django_number_place.number_place': number_place_data_files,
		},
		license='BSD License',
		description='A simple Django app to solve Number Place (called Sudoku) stepwise.',
		long_description=README,
		url='https://www.github.com/shun-tucorin/django_number_place',
		author='shun',
		author_email='shun@tucorin.com',
		classifiers=[
			'Environment :: Web Environment',
			'Framework :: Django',
			'Framework :: Django :: 2.2',
			'Framework :: Django :: 3.0',
			'Intended Audience :: Developers',
			'License :: OSI Approved :: BSD License',
			'Operating System :: OS Independent',
			'Programming Language :: Python :: 3.7',
			'Programming Language :: Python :: 3.8',
			'Topic :: Internet :: WWW/HTTP',
			'Topic :: Internet :: WWW/HTTP :: Dynamic Content',
		],
		ext_modules=cythonize(ext_modules),
		py_modules=['django_number_place'],
		zip_safe=False,
	)


if __name__ == '__main__':
	main()

