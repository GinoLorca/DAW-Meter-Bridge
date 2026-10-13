"""Every source file must parse as Python 3.7 (Live 11), and only the glue may import Live."""

import ast
import os
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

PACKAGE = os.path.join(_ROOT, "MeterBridge")
GLUE = "live_surface.py"
LIVE_MODULES = ("Live", "_Framework", "ableton")


def python_files(root):
    found = []
    for directory, subdirectories, files in os.walk(root):
        subdirectories[:] = [d for d in subdirectories if d != "__pycache__"]
        for name in files:
            if name.endswith(".py"):
                found.append(os.path.join(directory, name))
    return sorted(found)


def read(path):
    with open(path, "rb") as handle:
        return handle.read().decode("utf-8")


class SyntaxTests(unittest.TestCase):
    def test_parse_check_rejects_newer_syntax(self):
        # Proves the feature_version check below enforces 3.7 on this interpreter.
        # Python 3.9's parser ignores feature_version for some syntax; the explicit
        # node scan in test_no_python_38_constructs covers that case.
        try:
            ast.parse("if (n := 1):\n    pass\n", feature_version=(3, 7))
        except SyntaxError:
            return
        self.skipTest("this Python's ast.parse does not enforce feature_version; use 3.10+ for the full check")

    def test_no_python_38_constructs(self):
        newer_nodes = tuple(
            getattr(ast, name) for name in ("NamedExpr", "Match", "TryStar", "TypeAlias") if hasattr(ast, name)
        )
        for path in python_files(_ROOT):
            tree = ast.parse(read(path))
            for node in ast.walk(tree):
                with self.subTest(path=os.path.relpath(path, _ROOT), line=getattr(node, "lineno", 0)):
                    self.assertNotIsInstance(node, newer_nodes)
                    if isinstance(node, ast.arguments):
                        self.assertEqual(getattr(node, "posonlyargs", []), [])
                    if isinstance(node, ast.JoinedStr):
                        # f"{x=}" (3.8) leaves a literal ending in "=" before the value.
                        for left, right in zip(node.values, node.values[1:]):
                            if isinstance(left, ast.Constant) and isinstance(right, ast.FormattedValue):
                                self.assertFalse(str(left.value).rstrip().endswith("="), "f-string = specifier")

    def test_every_source_file_parses_as_python_37(self):
        files = python_files(_ROOT)
        self.assertGreater(len(files), 10)
        for path in files:
            with self.subTest(path=os.path.relpath(path, _ROOT)):
                ast.parse(read(path), filename=path, feature_version=(3, 7))

    def test_script_package_has_the_expected_modules(self):
        names = set(os.listdir(PACKAGE))
        for name in ("__init__.py", GLUE, "bridge.py", "protocol.py", "transport.py", "tracks.py",
                     "surfaces.py", "commands.py", "meters.py", "subscription.py", "volume_curve.py", "log.py"):
            self.assertIn(name, names)

    def test_only_the_glue_imports_live_at_module_level(self):
        for path in python_files(PACKAGE):
            tree = ast.parse(read(path), feature_version=(3, 7))
            imported = set()
            for node in tree.body:
                if isinstance(node, ast.Import):
                    imported.update(alias.name.split(".")[0] for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    imported.add(node.module.split(".")[0])
            live_imports = imported.intersection(LIVE_MODULES)
            with self.subTest(path=os.path.basename(path)):
                if os.path.basename(path) == GLUE:
                    self.assertEqual(live_imports, {"Live", "_Framework"})
                else:
                    self.assertEqual(live_imports, set())

    def test_no_annotations_or_fstrings_in_the_script(self):
        # Keeps the script on the safe side of 3.7: no runtime annotations to evaluate,
        # and plain %-formatting like Ableton's own scripts.
        for path in python_files(PACKAGE):
            tree = ast.parse(read(path), feature_version=(3, 7))
            for node in ast.walk(tree):
                with self.subTest(path=os.path.basename(path), line=getattr(node, "lineno", 0)):
                    self.assertNotIsInstance(node, ast.JoinedStr)
                    self.assertNotIsInstance(node, ast.AnnAssign)
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        self.assertIsNone(node.returns)
                        for argument in node.args.args + node.args.kwonlyargs:
                            self.assertIsNone(argument.annotation)

    def test_script_does_not_subclass_mackie_control(self):
        for path in python_files(PACKAGE):
            tree = ast.parse(read(path), feature_version=(3, 7))
            for node in ast.walk(tree):
                if isinstance(node, ast.ClassDef):
                    bases = [ast.dump(base) for base in node.bases]
                    with self.subTest(cls=node.name):
                        self.assertFalse(any("MackieControl" in base for base in bases))


if __name__ == "__main__":
    unittest.main()
