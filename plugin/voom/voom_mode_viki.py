# voom_mode_viki.py
# VOoM (Vim Outliner of Markers): two-pane outliner and related utilities
# plugin for Python-enabled Vim version 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author:  Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: This program is free software. It comes without any warranty,
#          to the extent permitted by applicable law. You can redistribute it
#          and/or modify it under the terms of the Do What The Fuck You Want To
#          Public License, Version 2, as published by Sam Hocevar.
#          See http://sam.zoy.org/wtfpl/COPYING for more details.

"""
VOoM markup mode for headline markup used by Vim Viki/Deplate plugin, Emacs
Org-mode. See |voom_mode_viki|.

* headline level 1
some text
** headline level 2
more text
*** headline level 3
**** headline level 4
etc.

First * must be at start of line.
There must be a space after last * .
"""

import re
headline_match = re.compile(r'^(\*+) ').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for list of Body lines.
    blines can also be Vim buffer object.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith('*'):
            continue
        bline = blines[i]
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[lev:].strip()
        tline = '  %s|%s' %('. '*(lev-1), head)
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines, column).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    column is cursor position in new headline in Body buffer.
    """
    tree_head = 'NewHeadline'
    bodyLines = ['%s NewHeadline' %('*'*level), '']
    column = level+2
    return (tree_head, bodyLines, column)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    s = '*'*(level+levDelta)
    return '%s %s' %(s, h[m.end(1)+1:])

