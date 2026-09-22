"""Optional parser-only check; NOT a replacement for flutter analyze/test.
pip install tree-sitter tree-sitter-dart
"""
from pathlib import Path
import tree_sitter
import tree_sitter_dart
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_dart.language()))
root = Path(__file__).resolve().parents[1]
errors = []
files = list((root / 'lib').rglob('*.dart')) + list((root / 'test').rglob('*.dart'))
for path in files:
    tree = parser.parse(path.read_bytes())
    def walk(node):
        if node.type == 'ERROR' or node.is_missing:
            errors.append(f'{path.relative_to(root)}:{node.start_point.row + 1}: {node.type}')
        for child in node.children:
            walk(child)
    walk(tree.root_node)
if errors:
    raise SystemExit('\n'.join(errors))
print(f'PASS: {len(files)} Dart files parsed without syntax errors. Types/plugins unverified.')
