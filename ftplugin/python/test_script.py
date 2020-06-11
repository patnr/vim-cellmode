a = 3
b = 4
c = 5

c

def cmd(args,split=True, **kwargs):
    """Run subprocess and communicate."""
    if split:
        args = args.split()
    # Cannot use capture_output for python <= 3.6
    # => Use stdout=PIPE
    ps = subprocess.run(args, check=True, stdout=PIPE, **kwargs)
    output = ps.stdout.decode()
    return output







def my_ast_printer(thing):
    if hasattr(thing, 'id'):
        # Avoid recursion for one particular var-name (___x___)
        ___x___ = thing.id
        if ___x___ != '___x___':
            try: eval(___x___)
            except NameError: return
            print(___x___, ':', sep='')
            ___x___ = str(eval(___x___))
            ___x___ = '    ' + '    \\n'.join(___x___.split('\\n'))
            print(___x___)

import ast as ___ast
class ___Visitor(___ast.NodeVisitor):

    # For lines w/ a single variable
    def visit_Expr(self, node):
        my_ast_printer(node.value)
        self.generic_visit(node)

    # For lines w/ assignments
    def visit_Assign(self, node):
        for target in node.targets:
            my_ast_printer(target)
        self.generic_visit(node)

___Visitor().visit(___ast.parse(open(__file__).read()))
del my_ast_printer, ___Visitor 

