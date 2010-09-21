"""
VOoM markup mode for vimwiki headline markup.
    http://www.vim.org/scripts/script.php?script_id=2226

Like main wiki mode except that:
    there can be leading whitespace (centered headline?)
    HTML comment tags are not stripped

= headline level 1 =
body text
== headline level 2 ==
body text
=== headline level 3 ===
    === headline level 3 ===
==== level 4 ====

"""

# can access main module voom.py, including global outline data
#import sys
#if 'voom' in sys.modules:
    #voom = sys.modules['voom']
    #VOOMS = voom.VOOMS

import re
headline_match = re.compile(r'^\s*(=+).+(\1)\s*$').match


def hook_makeOutline(body, blines):
    """Return (tlines, bnodes, levels) for list of Body lines.
    blines can also be Vim buffer object.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, nodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i]
        bline = bline.strip()
        if not bline.startswith('='):
            continue
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        bline = bline.strip()
        head = bline[lev:-lev].strip()
        tline = '  %s|%s' %('. '*(lev-1), head)
        tlines_add(tline)
        nodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def hook_newHeadline(body, level):
    """Return (tree_head, bodyLines, column).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    column is cursor position in new headline in Body buffer.
    """
    tree_head = 'NewHeadline'
    bodyLines = ['%sNewHeadline%s' %('='*level,'='*level), '']
    column = level+1
    return (tree_head, bodyLines, column)


def hook_changeLevBodyHead(body, h, delta):
    """Increase of decrease level number of Body headline by delta."""
    if delta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    s = '='*(level+delta)
    return '%s%s%s%s%s' %(h[:m.start(1)], s, h[m.end(1):m.start(2)], s, h[m.end(2):])

