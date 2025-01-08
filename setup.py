import setuptools

with open("README.md", "r") as fh:
    long_description = fh.read()

from pythondata_misc_xosera import version_str

setuptools.setup(
    name="pythondata-misc-xosera",
    version=version_str,
    author="LiteX Authors",
    author_email="litex@googlegroups.com",
    description="""\
Python module containing verilog files for Xosera misc.""",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/litex-hub/pythondata-misc-xosera",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: The MIT License (MIT)",
        "Operating System :: OS Independent",
    ],
    python_requires='>=3.5',
    zip_safe=False,
    packages=setuptools.find_packages(),
    package_data={
    	'misc_xosera': ['misc_xosera/verilog/**'],
    },
    include_package_data=True,
    project_urls={
        "Bug Tracker": "https://github.com/litex-hub/pythondata-misc-xosera/issues",
        "Source Code": "https://github.com/litex-hub/pythondata-misc-xosera",
    },
)
