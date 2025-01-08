import os.path
__dir__ = os.path.split(os.path.abspath(os.path.realpath(__file__)))[0]
data_location = os.path.join(__dir__, "verilog")
src = "https://github.com/XarkLabs/Xosera.git"

# Module version
version_str = "0.0.post1429"
version_tuple = (0, 0, 1429)
try:
    from packaging.version import Version as V
    pversion = V("0.0.post1429")
except ImportError:
    pass

# Data version info
data_version_str = "0.0.post1281"
data_version_tuple = (0, 0, 1281)
try:
    from packaging.version import Version as V
    pdata_version = V("0.0.post1281")
except ImportError:
    pass
data_git_hash = "51967d8c17409c151ba546f93be97f16375868f2"
data_git_describe = "v0.0-1281-g51967d8"
data_git_msg = """\
commit 51967d8c17409c151ba546f93be97f16375868f2
Author: Xark <XarkLabs@users.noreply.github.com>
Date:   Tue Oct 1 18:55:25 2024 -0700

    Update REFERENCE.md
    
    Fix bit definitions for Px_V_SCROLL and try to clarify descriptions.

"""

# Tool version info
tool_version_str = "0.0.post148"
tool_version_tuple = (0, 0, 148)
try:
    from packaging.version import Version as V
    ptool_version = V("0.0.post148")
except ImportError:
    pass


def data_file(f):
    """Get absolute path for file inside pythondata_misc_xosera."""
    fn = os.path.join(data_location, f)
    fn = os.path.abspath(fn)
    if not os.path.exists(fn):
        raise IOError("File {f} doesn't exist in pythondata_misc_xosera".format(f))
    return fn
