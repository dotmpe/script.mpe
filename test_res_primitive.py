import unittest

from zope.interface.verify import verifyObject
from zope.component import getGlobalSiteManager

import res.primitive
import res.iface


def test_tree_traverse():
    tree = res.primitive.TreeNodeDict('<root>')
    tree.append(res.primitive.TreeNodeDict('<node>'))
    assert tree.nodeid == '<root>'
    verifyObject( res.iface.Node, tree )
    verifyObject( res.iface.ITree, tree )
    #visitor = AbstractHierarchicalVisitor()
    visitor = res.primitive.NodeIDExtractor()
    r = visitor.traverse(tree)
    print __name__, list(r)

def test_dictnode_fs_populate(): # TEST creating a dicttree from fs
    root = 'res'
    gsm = getGlobalSiteManager()
    localfs_service = gsm.queryUtility(res.iface.ILocalNodeService, 'fs')
    rootnode = localfs_service(root)
    tree = res.primitive.TreeNodeDict(None)
    visitor = res.primitive.DictNodeUpdater(tree)
    tree.travel(rootnode, visitor)
    list ( visitor.traverse( rootnode ) )
    
    import confparse
    opts = confparse.Values({})
    tree_init = {}
    res.fs.Dir.tree( root, opts, tree_init )


class TestResPrimitive(unittest.TestCase):
    def test_1_tree_traverse(self):
        test_tree_traverse()
    def test_2_dictnote_fs_populate(self):
        test_dictnode_fs_populate()


if __name__ == '__main__':
    unittest.main()
