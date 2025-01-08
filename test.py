#!/usr/bin/env python3

from __future__ import print_function

import os

import pythondata_misc_xosera

print("Found xosera @ version", pythondata_misc_xosera.version_str, "(with data", pythondata_misc_xosera.data_version_str, ")")
print()
print("Data is in", pythondata_misc_xosera.data_location)
assert os.path.exists(pythondata_misc_xosera.data_location)
print("Data is version", pythondata_misc_xosera.data_version_str, pythondata_misc_xosera.data_git_hash)
print("-"*75)
print(pythondata_misc_xosera.data_git_msg)
print("-"*75)
print()
print("It contains:")
for root, dirs, files in os.walk(pythondata_misc_xosera.data_location):
    dirs.sort()
    for f in sorted(files):
        path = os.path.relpath(os.path.join(root, f), pythondata_misc_xosera.data_location)
        print(" -", path)
