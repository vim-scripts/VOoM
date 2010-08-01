# voom.py
# VOoM (Vim Outliner of Markers): two-pane outliner and related utilities
# plugin for Python-enabled Vim version 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author:  Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: This program is free software. It comes without any warranty,
#          to the extent permitted by applicable law. You can redistribute it
#          and/or modify it under the terms of the Do What The Fuck You Want To
#          Public License, Version 2, as published by Sam Hocevar.
#          See http://sam.zoy.org/wtfpl/COPYING for more details.
# Version: 3.0, 2010-08-01

"""This module is meant to be imported by voom.vim ."""

import vim
import sys, os, re
import traceback
import bisect
# lazy imports
random = None

#Vim = sys.modules['__main__']

# see voom.vim for conventions
# voom_WhatEver() means it's Python code for Voom_WhatEver() Vim function


#---Constants and Settings--------------------{{{1

# default start fold marker and regexp
MARKER = '{{{'                             # }}}
MARKER_RE = re.compile(r'{{{(\d+)(x?)')    # }}}

voom_dir = vim.eval('s:voom_dir')
voom_script = vim.eval('s:voom_script_py')

# {filetype: make_head_<filetype> function, ...}
MAKE_HEAD = {}


class VoomData: #{{{1
    """Container for global data."""
    def __init__(self):
        # Vim buffer objects, {bnr : vim.buffer, ...}
        self.buffers = {}
        # {body: [Body lnums of headlines], ...}
        self.bnodes ={}
        # {body: [headline levels], ...}
        self.levels ={}
        # {body : snLn, ...}
        self.snLns = {}
        # {body : first Tree line, ...}
        self.names = {}
        # {body : &filetype, ...}
        self.filetypes = {}
        # {body : chars to strip from right side of Tree headlines, ...}
        self.rstrip_chars = {}
        # {body : start fold marker if not default, ...}
        self.markers = {}
        # {body : start fold marker regexp if not default, ...}
        self.markers_re = {}

#VOOM=VoomData()
# VOOM, an instance of VoomData, is created from voom.vim, not here.
# Thus, this module can be reloaded without destroying data.


#---Outline Construction----------------------{{{1


def makeOutline(body, blines): #{{{2
    """Return (tlines, bnodes, levels) for list of Body lines.
    Optimized for lists in which most items don't have fold markers.
    blines can also be Vim buffer object (slower, see v3.0 notes).
    """
    marker = VOOM.markers.get(body, MARKER)
    marker_re_search = VOOM.markers_re.get(body, MARKER_RE).search
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, nodes_add, levels_add = tlines.append, bnodes.append, levels.append
    h = MAKE_HEAD.get(VOOM.filetypes[body], 0)
    # NOTE: duplicate code, only head construction is different
    if not h:
        c = VOOM.rstrip_chars[body]
        for i in xrange(Z):
            if not marker in blines[i]: continue
            bline = blines[i]
            match = marker_re_search(bline)
            if not match: continue
            lev = int(match.group(1))
            head = bline[:match.start()].lstrip().rstrip(c).strip('-=~').strip()
            tline = ' %s%s%s%s' %(match.group(2) or ' ', '. '*(lev-1), '|', head)
            tlines_add(tline)
            nodes_add(i+1)
            levels_add(lev)
    else:
        for i in xrange(Z):
            if not marker in blines[i]: continue
            bline = blines[i]
            match = marker_re_search(bline)
            if not match: continue
            lev = int(match.group(1))
            head = h(bline,match)
            tline = ' %s%s%s%s' %(match.group(2) or ' ', '. '*(lev-1), '|', head)
            tlines_add(tline)
            nodes_add(i+1)
            levels_add(lev)
    return (tlines, bnodes, levels)


#--- make_head functions --- {{{2

def make_head_html(bline,match):
    s = bline[:match.start()].strip().strip('-=~').strip()
    if s.endswith('<!'):
        return s[:-2].strip()
    else:
        return s
MAKE_HEAD['html'] = make_head_html

#def make_head_vim(bline,match):
#    return bline[:match.start()].lstrip().rstrip('" \t').strip('-=~').strip()
#MAKE_HEAD['vim'] = make_head_vim

#def make_head_py(bline,match):
#    return bline[:match.start()].lstrip().rstrip('# \t').strip('-=~').strip()
#for ft in 'python ruby perl tcl'.split():
#    MAKE_HEAD[ft] = make_head_py


def updateTree(body,tree): #{{{2
    """Construct outline for Body body.
    Update lines in Tree buffer if needed.
    This can be run from any buffer as long as Tree is set to ma.
    """
    ##### Construct outline #####
    #blines = VOOM.buffers[body][:] # wasteful, see v3.0 notes
    Body = VOOM.buffers[body]
    tlines, bnodes, levels  = makeOutline(body, Body)
    tlines[0:0], bnodes[0:0], levels[0:0] = [VOOM.names[body]], [1], [1]
    VOOM.bnodes[body], VOOM.levels[body] = bnodes, levels

    ##### Add the = mark #####
    snLn = VOOM.snLns[body]
    Z = len(VOOM.bnodes[body])
    # snLn got larger than the number of nodes because some nodes were
    # deleted while editing the Body
    if snLn > Z:
        snLn = Z
        vim.command('call Voom_SetSnLn(%s,%s)' %(body,snLn))
        VOOM.snLns[body] = snLn
    tlines[snLn-1] = '=%s' %tlines[snLn-1][1:]

    ##### Compare Tree lines, draw as needed ######
    # Draw all Tree lines only when needed. This is optimization for large
    # outlines, e.g. >1000 Tree lines. Drawing all lines is slower than
    # comparing all lines and then drawing nothing or just one line.

    Tree = VOOM.buffers[tree]
    #tlines_ = Tree[:]
    if not len(Tree)==len(tlines):
        Tree[:] = tlines
        return

    # If only one line is modified, draw that line only. This ensures that
    # editing (and inserting) a single headline in a large outline is fast.
    # If more than one line is modified, draw all lines from first changed line
    # to the end of buffer.
    draw_one = False
    for i in xrange(len(tlines)):
        if not tlines[i]==Tree[i]:
            if draw_one==False:
                draw_one = True
                diff = i
            else:
                Tree[diff:] = tlines[diff:]
                return
    if draw_one:
        Tree[diff] = tlines[diff]


def computeSnLn(body, blnr): #{{{2
    """Compute Tree lnum for node at line blnr in Body body.
    Assign Vim and Python snLn vars.
    """
    # snLn should be 1 if blnr is before the first node, top of Body
    snLn = bisect.bisect_right(VOOM.bnodes[body], blnr)
    vim.command('call Voom_SetSnLn(%s,%s)' %(body,snLn))
    VOOM.snLns[body] = snLn


def verifyTree(body,tree): #{{{2
    """Verify Tree and VOOM data."""
    tlines_ = VOOM.buffers[tree][:]
    #blines = VOOM.buffers[body][:]
    blines = VOOM.buffers[body]
    tlines, bnodes, levels  = makeOutline(body, blines)
    tlines[0:0], bnodes[0:0], levels[0:0] = [VOOM.names[body]], [1], [1]
    snLn = VOOM.snLns[body]
    tlines[snLn-1] = '=%s' %tlines[snLn-1][1:]

    if not tlines_ == tlines:
        #print 'VOoM: DIFFERENT tree lines'
        vim.command("echoerr 'VOoM: DIFFERENT tree lines'")
    if not VOOM.bnodes[body] == bnodes:
        #print 'VOoM: DIFFERENT bnodes'
        vim.command("echoerr 'VOoM: DIFFERENT bnodes'")
    if not VOOM.levels[body] == levels:
        #print 'VOoM: DIFFERENT levels'
        vim.command("echoerr 'VOoM: DIFFERENT levels'")


def voom_Init(body): #{{{2
    """This is part of Voom_Init(), called from Body."""
    VOOM.buffers[body] = vim.current.buffer
    VOOM.snLns[body] = 1
    VOOM.names[body] = vim.eval('l:firstLine')

    marker = vim.eval('&foldmarker').split(',')[0]
    if not marker=='{{{': # }}}
        VOOM.markers[body] = marker
        VOOM.markers_re[body] = re.compile(re.escape(marker) + r'(\d+)(x?)')

    VOOM.filetypes[body] = vim.eval('&filetype')

    if vim.eval("has_key(g:voom_rstrip_chars,&ft)")=="1":
        rstrip_chars = vim.eval("g:voom_rstrip_chars[&ft]")
    else:
        rstrip_chars = vim.eval("&commentstring").split('%s')[0].strip() + " \t"
    VOOM.rstrip_chars[body] = rstrip_chars


def voom_TreeCreate(): #{{{2
    """This is part of Voom_TreeCreate(), called from Tree."""
    body = int(vim.eval('a:body'))
    blnr = int(vim.eval('l:blnr')) # Body cursor lnum
    bnodes = VOOM.bnodes[body]
    Body = VOOM.buffers[body]
    # current Body lnum
    z = len(bnodes)

    ### compute snLn, create Tree folding

    # find bnode marked with '='
    # find bnodes marked with 'o'
    snLn = 0
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    marker_re_search = marker_re.search
    oFolds = []
    for i in xrange(1,z):
        bline = Body[bnodes[i]-1]
        # part of Body headline after marker+level+'x'
        bline2 = bline[marker_re_search(bline).end():]
        if not bline2: continue
        if bline2[0]=='=':
            snLn = i+1
        elif bline2[0]=='o':
            oFolds.append(i+1)
            if bline2[1:] and bline2[1]=='=':
                snLn = i+1

    # create Tree folding
    if oFolds:
        cFolds = foldingFlip(2,z,oFolds,body)
        foldingCreate(2,z,cFolds)

    if snLn:
        vim.command('call Voom_SetSnLn(%s,%s)' %(body,snLn))
        VOOM.snLns[body] = snLn
        # set blnShow if Body cursor is on or before the first headline
        if z > 1 and blnr <= bnodes[1]:
            vim.command('let l:blnShow=%s' %bnodes[snLn-1])
    else:
        # no Body headline is marked with =
        # select current Body node
        computeSnLn(body, blnr)


def voom_UnVoom(): #{{{2
    body, tree = int(vim.eval('a:body')), int(vim.eval('a:tree'))
    if tree in VOOM.buffers: del VOOM.buffers[tree]
    if body in VOOM.buffers: del VOOM.buffers[body]
    if body in VOOM.bnodes:   del VOOM.bnodes[body]
    if body in VOOM.levels:  del VOOM.levels[body]
    if body in VOOM.snLns:   del VOOM.snLns[body]
    if body in VOOM.names:   del VOOM.names[body]
    if body in VOOM.filetypes: del VOOM.filetypes[body]
    if body in VOOM.rstrip_chars: del VOOM.rstrip_chars[body]
    if body in VOOM.markers:    del VOOM.markers[body]
    if body in VOOM.markers_re: del VOOM.markers_re[body]


#---Outline Traversal-------------------------{{{1
# Functions for getting node's parents, children, ancestors, etc.
# Nodes here are Tree buffer lnums.
# All we do is traverse VOOM.levels[body].


def nodeHasChildren(body, lnum): #{{{2
    """Determine if node at Tree line lnum has children."""
    levels = VOOM.levels[body]
    if lnum==1 or lnum==len(levels): return False
    elif levels[lnum-1] < levels[lnum]: return True
    else: return False


def nodeSubnodes(body, lnum): #{{{2
    """Number of all subnodes for node at Tree line lnum."""
    levels = VOOM.levels[body]
    z = len(levels)
    if lnum==1 or lnum==z: return 0
    lev = levels[lnum-1]
    for i in xrange(lnum,z):
        if levels[i]<=lev:
            return i-lnum
    return z-lnum


def nodeParent(body, lnum): #{{{2
    """Return lnum of closest parent of node at Tree line lnum."""
    levels = VOOM.levels[body]
    lev = levels[lnum-1]
    if lev==1: return None
    for i in xrange(lnum-2,0,-1):
        if levels[i] < lev: return i+1


def nodeAncestors(body, lnum): #{{{2
    """Return lnums of ancestors of node at Tree line lnum."""
    levels = VOOM.levels[body]
    lev = levels[lnum-1]
    if lev==1: return []
    ancestors = []
    for i in xrange(lnum-2,0,-1):
        levi = levels[i]
        if levi < lev:
            lev = levi
            ancestors.append(i+1)
            if lev==1:
                ancestors.reverse()
                return ancestors


def nodeUNL(body,tree, lnum): #{{{2
    """Compute UNL of node at Tree line lnum.
    Return list of headlines.
    """
    Tree = VOOM.buffers[tree]
    levels = VOOM.levels[body]
    if lnum==1: return ['top-of-file']
    parents = nodeAncestors(body,lnum)
    parents.append(lnum)
    heads = [Tree[ln-1].split('|',1)[1] for ln in parents]
    return heads


def nodeSiblings(body, lnum): #{{{2
    """Return lnums of siblings for node at Tree line lnum.
    These are nodes with the same parent and level as lnum node. Sorted in
    ascending order. lnum itself is included. First node (lnum 1) is never
    included, that is minimum lnum in results is 2.
    """
    levels = VOOM.levels[body]
    lev = levels[lnum-1]
    siblings = []
    # scan back
    for i in xrange(lnum-1,0,-1):
        levi = levels[i]
        if levi < lev:
            break
        elif levi==lev:
            siblings[0:0] = [i+1]
    # scan forward
    for i in xrange(lnum,len(levels)):
        levi = levels[i]
        if levi < lev:
            break
        elif levi==lev:
            siblings.append(i+1)
    return siblings


def getSiblingsGroups(body, siblings): #{{{2
    """Return list of groups of siblings in the region defined by 'siblings'
    group, which is list of siblings in ascending order (Tree lnums).
    Siblings in each group are nodes with the same parent and level.
    Siblings in each group are in ascending order.
    List of groups is reverse-sorted by level of siblings and by parent lnum:
        from RIGHT TO LEFT and from BOTTOM TO TOP.
    """
    levels = VOOM.levels[body]
    lnum1, lnum2 = siblings[0], siblings[-1]
    lnum2 = lnum2 + nodeSubnodes(body,lnum2)

    # get all parents (nodes with children) in the range
    parents = [i for i in xrange(lnum1,lnum2) if levels[i-1]<levels[i]]
    if not parents:
        return [siblings]

    # get children for each parent
    results_dec = [(levels[lnum1-1], 0, siblings)]
    for p in parents:
        sibs = [p+1]
        lev = levels[p] # level of siblings of this parent
        for i in xrange(p+1, lnum2):
            levi = levels[i]
            if levi==lev:
                sibs.append(i+1)
            elif levi < lev:
                break
        results_dec.append((lev, p, sibs))

    results_dec.sort()
    results_dec.reverse()
    results = [i[2] for i in results_dec]
    assert len(parents)+1 == len(results)
    return results


#---Outline Navigation------------------------{{{1


def voom_TreeSelect(): #{{{2
    # Get first and last lnums of Body node for Tree line lnum.
    lnum = int(vim.eval('a:lnum'))
    body = int(vim.eval('l:body'))
    VOOM.snLns[body] = lnum

    nodeStart =  VOOM.bnodes[body][lnum-1]
    vim.command('let l:nodeStart=%s' %nodeStart)

    if lnum==len(VOOM.bnodes[body]): # last node
        vim.command("let l:nodeEnd=%s" %(len(VOOM.buffers[body])+1))
    else:
        # "or 1" takes care of situation when:
        # lnum is 1 (path info line);
        # first Body line is a headline.
        # In that case VOOM.bnodes is [1, 1, ...]
        nodeEnd =  VOOM.bnodes[body][lnum]-1 or 1
        vim.command('let l:nodeEnd=%s' %nodeEnd)


def voom_TreeToStartupNode(): #{{{2
    body = int(vim.eval('l:body'))
    bnodes = VOOM.bnodes[body]
    Body = VOOM.buffers[body]
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    z = len(bnodes)
    # find Body headlines marked with '='
    lnums = []
    for i in xrange(1,z):
        bline = Body[bnodes[i]-1]
        # part of Body headline after marker+level+'x'+'o'
        bline2 = bline[marker_re.search(bline).end():]
        if not bline2: continue
        if bline2[0]=='=':
            lnums.append(i+1)
        elif bline2[0]=='o':
            if bline2[1:] and bline2[1]=='=':
                lnums.append(i+1)
    vim.command('let l:lnums=%s' %repr(lnums))


def voom_EchoUNL(): #{{{2
    buftype = vim.eval('l:buftype')
    body = int(vim.eval('l:body'))
    tree = int(vim.eval('l:tree'))
    lnum = int(vim.eval('l:lnum'))

    if buftype=='body':
        lnum = bisect.bisect_right(VOOM.bnodes[body], lnum)

    heads = nodeUNL(body,tree,lnum)
    UNL = ' -> '.join(heads)
    vim.command("let @n='%s'" %UNL.replace("'", "''"))
    for h in heads[:-1]:
        h = h.replace("'", "''")
        vim.command("echohl ModeMsg")
        vim.command("echon '%s'" %h)
        vim.command("echohl Title")
        vim.command("echon ' -> '")
    h = heads[-1].replace("'", "''")
    vim.command("echohl ModeMsg")
    vim.command("echon '%s'" %h)
    vim.command("echohl None")


def voom_Grep(): #{{{2
    body = int(vim.eval('l:body'))
    tree = int(vim.eval('l:tree'))
    bnodes = VOOM.bnodes[body]
    matchesAND, matchesNOT = vim.eval('l:matchesAND'), vim.eval('l:matchesNOT')

    # convert blnums of mathes into tlnums, that is node numbers
    tlnumsAND, tlnumsNOT = [], [] # lists of AND and NOT "tlnums" dicts
    counts = {} # {tlnum: count of all AND matches in this node, ...}
    blnums = {} # {tlnum: first AND match in this node, ...}
    for L in matchesAND:
        tlnums = {} # {tlnum of node with a match:0, ...}
        L.pop()
        for bln in L:
            bln = int(bln)
            tln = bisect.bisect_right(bnodes, bln)
            if not tln in blnums:
                blnums[tln] = bln
            elif blnums[tln] > bln:
                blnums[tln] = bln
            if tln in counts:
                counts[tln]+=1
            else:
                counts[tln] = 1
            tlnums[tln] = 0
        tlnumsAND.append(tlnums)
    for L in matchesNOT:
        tlnums = {} # {tlnum of node with a match:0, ...}
        L.pop()
        for bln in L:
            bln = int(bln)
            tln = bisect.bisect_right(bnodes, bln)
            tlnums[tln] = 0
        tlnumsNOT.append(tlnums)

    # if there are only NOT patterns
    if not matchesAND:
        tlnumsAND = [{}.fromkeys(range(1,len(bnodes)+1))]

    # compute intersection
    results = intersectDicts(tlnumsAND, tlnumsNOT)
    results = results.keys()
    results.sort()
    #print results

    # need this to left-align UNLs in the qflist
    max_size = 0
    for t in results:
        if not matchesAND:
            blnums[t] = bnodes[t-1]
            counts[t] = 0
        size = len('%s%s%s' %(t, counts[t], blnums[t]))
        if size > max_size:
            max_size = size

    # list of dictionaries for setloclist() or setqflist()
    loclist = []
    for t in results:
        size = len('%s%s%s' %(t, counts[t], blnums[t]))
        spaces = ' '*(max_size - size)
        UNL = ' -> '.join(nodeUNL(body,tree,t)).replace("'", "''")
        text = 'n%s:%s%s|%s' %(t, counts[t], spaces, UNL)
        d = "{'text':'%s', 'lnum':%s, 'bufnr':%s}, " %(text, blnums[t], body)
        loclist .append(d)
    #print '\n'.join(loclist)

    vim.command("call setqflist([%s],'a')" %(''.join(loclist)) )


def intersectDicts(dictsAND, dictsNOT): #{{{2
    """Arguments are two lists of dictionaries. Keys are Tree lnums.
    Return dict: intersection of all dicts in dictsAND and non-itersection with
    all dicts in dictsNOT.
    """
    if not dictsAND: return {}
    D1 = dictsAND[0]
    if len(dictsAND)==1:
        res = D1
    else:
        res = {}
    # get intersection with all other AND dicts
    for D in dictsAND[1:]:
        for item in D1:
            if item in D: res[item] = 0
    # get non-intersection with NOT dicts
    for D in dictsNOT:
        keys = res.keys()
        for key in keys:
            if key in D: del res[key]
    return res


#---Outline Operations------------------------{{{1
# voom_Oop... functions are called from Voom_Oop... Vim functions.
# They use local Vim vars set by the caller and can create and change Vim vars.
# They set lines in Tree and Body via vim.buffer objects.
# Default l:blnShow is -1.
# Returning before setting l:blnShow means no changes were made.


def changeLevTreeHead(h, delta): #{{{2
    """Increase of decrese level of Tree headline by delta:
    insert or delete  delta*". "  string.
    """
    if delta>0:
        return '%s%s%s' %(h[:2], '. '*delta, h[2:])
    elif delta<0:
        return '%s%s' %(h[:2], h[2-2*delta:])
    else:
        return h


def changeLevBodyHead(h, delta, body): #{{{2
    """Increase of decrese level number of Body headline by delta."""
    if delta==0: return h
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    m = marker_re.search(h)
    level = int(m.group(1))
    return '%s%s%s' %(h[:m.start(1)], level+delta, h[m.end(1):])


def setClipboard(s): #{{{2
    """Set Vim + register (system clipboard) to string s."""
    if not s: return
    # use '%s' for Vim string: all we need to do is double ' quotes
    s = s.replace("'", "''")
    vim.command("let @+='%s'" %s)


def voom_OopSelEnd(): #{{{2
    """This is part of Voom_Oop() checks.
    Selection in Tree starts at line ln1 and ends at line ln2.
    Selection can have many sibling nodes: nodes with the same level as ln1 node.
    Return lnum of last node in the last sibling node's branch.
    Return 0 if selection is invalid.
    """
    body = int(vim.eval('l:body'))
    ln1, ln2  = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    if ln1==1: return 0
    levels = VOOM.levels[body]
    z, lev0 = len(levels), levels[ln1-1]
    for i in xrange(ln1,z):
        lev = levels[i]
        # invalid selection: there is node with level smaller than that of ln1 node
        if i+1 <= ln2 and lev < lev0: return 0
        # node after the last sibling node's branch
        elif i+1 > ln2 and lev <= lev0: return i
    return z


def voom_OopInsert(as_child=False): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln, ln_status = int(vim.eval('l:ln')), vim.eval('l:ln_status')
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    levels = VOOM.levels[body]

    # Compute where to insert and at what level.
    # Insert new headline after node at ln.
    # If node is folded, insert after the end of node's tree.
    # default level
    lev = levels[ln-1]
    # after first Tree line
    if ln==1: lev=1
    # as_child always inserts as first child of current node, even if it's folded
    elif as_child: lev+=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif lev < levels[ln]:
        # folded: insert after current node's branch, same level
        if ln_status=='folded': ln += nodeSubnodes(body,ln)
        # not folded, insert as child
        else: lev+=1

    # remove = mark before modifying Tree
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    # insert headline in Tree and Body
    # bLnum is new headline ln in Body
    marker = VOOM.markers.get(body, MARKER)
    treeLine = '= %s%sNewHeadline' %('. '*(lev-1), '|')
    bodyLine = '---NewHeadline--- %s%s' %(marker, lev)
    if ln==len(levels):
        Tree.append(treeLine)
        bLnum = len(Body)
        Body.append([bodyLine, ''])
    else:
        Tree[ln:ln] = [treeLine]
        bLnum = VOOM.bnodes[body][ln]-1
        Body[bLnum:bLnum] = [bodyLine, '']

    vim.command('let bLnum=%s' %(bLnum+1))

    # write = mark and set snLn to new headline
    Tree[ln] = '=' + Tree[ln][1:]
    VOOM.snLns[body] = ln+1
    vim.command('call Voom_SetSnLn(%s,%s)' %(body, ln+1))


def voom_OopPaste(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln, ln_status = int(vim.eval('l:ln')), vim.eval('l:ln_status')
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    levels, bnodes = VOOM.levels[body], VOOM.bnodes[body]

    ### clipboard
    pText = vim.eval('@+')
    if not pText:
        vim.command("call Voom_ErrorMsg('VOoM (Paste): clipboard is empty')")
        vim.command("call Voom_OopFromBody(%s,%s,-1,'noa')" %(body,tree))
        return
    blines = pText.split('\n') # Body lines to paste
    pTlines, pBnodes, pLevels = makeOutline(body, blines)

    ### verify that clipboard is a valid Voom text
    if pBnodes==[] or pBnodes[0]!=1:
        vim.command("call Voom_ErrorMsg('VOoM (Paste): invalid clipboard--no marker on first line')")
        vim.command("call Voom_OopFromBody(%s,%s,-1,'noa')" %(body,tree))
        return
    lev_ = pLevels[0]
    for lev in pLevels:
        # there is node with level smaller than that of the first node
        if lev < pLevels[0]:
            vim.command("call Voom_ErrorMsg('VOoM (Paste): invalid clipboard--root level error')")
            vim.command("call Voom_OopFromBody(%s,%s,-1,'noa')" %(body,tree))
            return
        # level incremented by 2 or more
        elif lev-lev_ > 1:
            vim.command("call Voom_WarningMsg('VOoM (Paste): inconsistent levels in clipboard--level incremented by >2', ' ')")
        lev_ = lev

    ### compute where to insert and at what level
    # insert nodes after node at ln at level lev
    # if node is folded, insert after the end of node's tree
    lev = levels[ln-1] # default level
    # after first Tree line
    if ln==1: lev=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif lev < levels[ln]:
        # folded: insert after current node's branch, same level
        if ln_status=='folded': ln += nodeSubnodes(body,ln)
        # not folded, insert as child
        else: lev+=1

    ### adjust levels of nodes being inserted
    levDelta = lev - pLevels[0]
    if levDelta:
        pTlines = [changeLevTreeHead(h, levDelta) for h in pTlines]
        pLevels = [(lev+levDelta) for lev in pLevels]
        for bl in pBnodes:
            blines[bl-1] = changeLevBodyHead(blines[bl-1], levDelta, body)

    ### insert body lines in Body
    if ln < len(bnodes): bln = bnodes[ln]-1
    else: bln = len(Body)
    Body[bln:bln] = blines

    ###### go back to Tree
    blnShow = bln+1
    vim.command("call Voom_OopFromBody(%s,%s,%s,'noa')" %(body,tree, blnShow))

    # remove = mark before modifying Tree
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### insert headlines in Tree; levels in levels
    Tree[ln:ln] = pTlines
    levels[ln:ln] = pLevels

    ### start and end lnums of inserted region
    ln1 = ln+1
    ln2 = ln+len(pBnodes)
    vim.command('let l:ln1=%s' %ln1)
    vim.command('let l:ln2=%s' %ln2)
    # set snLn to first headline of inserted nodes
    Tree[ln1-1] = '=' + Tree[ln1-1][1:]
    VOOM.snLns[body] = ln1

    ### update bnodes
    # increment bnodes being pasted
    for i in xrange(0,len(pBnodes)):
        pBnodes[i]+=bln
    # increment bnodes after pasted region
    delta = len(blines)
    for i in xrange(ln,len(bnodes)):
        bnodes[i]+=delta
    # insert pBnodes after ln
    bnodes[ln:ln] = pBnodes

    # we don't get here if previous code fails
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopCopy(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    # body lines to copy
    bln1 = bnodes[ln1-1]
    if ln2 < len(bnodes): bln2 = bnodes[ln2]-1
    else: bln2 = len(Body)
    blines = Body[bln1-1:bln2]

    setClipboard('\n'.join(blines))


def voom_OopCut(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnUp1 = int(vim.eval('l:lnUp1'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    ### copy and delete body lines
    bln1 = bnodes[ln1-1]
    if ln2 < len(bnodes): bln2 = bnodes[ln2]-1
    else: bln2 = len(Body)
    blines = Body[bln1-1:bln2]

    setClipboard('\n'.join(blines))
    Body[bln1-1:bln2] = []

    ###### go back to Tree
    blnShow = bnodes[lnUp1-1]
    vim.command('let l:blnShow=%s' %blnShow)
    vim.command("call Voom_OopFromBody(%s,%s,%s,'noa')" %(body,tree, blnShow))

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### delet tree lines, levels
    Tree[ln1-1:ln2] = []
    levels[ln1-1:ln2] = []

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VOOM.snLns[body] = lnUp1

    ### update bnodes
    # decrement lnums after deleted range
    delta = bln2-bln1+1
    for i in xrange(ln2,len(bnodes)):
        bnodes[i]-=delta
    # cut
    bnodes[ln1-1:ln2] = []

#  ..............
#  .............. blnUp1-1
#  ============== blnUp1=bnodes[lnUp1-1]
#  ..............
#  ============== bln1=bnodes[ln1-1]
#  range being
#  deleted
#  .............. bln2=bnodes[ln2]-1, can be last line
#  ==============
#  ..............


def voom_OopUp(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnUp1, lnUp2 = int(vim.eval('l:lnUp1')), int(vim.eval('l:lnUp2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    ### compute change in level
    # current level of root nodes in selection
    levOld = levels[ln1-1]
    # new level of root nodes in selection
    # lnUp1 is fist child of lnUp2, insert also as first child
    if levels[lnUp2-1] + 1 == levels[lnUp1-1]:
        levNew = levels[lnUp1-1]
    # all other cases, includes insertion after folded node
    else:
        levNew = levels[lnUp2-1]
    levDelta = levNew-levOld

    ### body lines to move
    bln1 = bnodes[ln1-1]
    if ln2 < len(bnodes): bln2 = bnodes[ln2]-1
    else: bln2 = len(Body)
    blines = Body[bln1-1:bln2]
    if levDelta:
        for bl in bnodes[ln1-1:ln2]:
            blines[bl-bln1] = changeLevBodyHead(blines[bl-bln1], levDelta, body)
    #print '-'*10; print '\n'.join(blines); print '-'*10

    ### move body lines: cut, then insert
    # insert before this line, it's the same before and after bnodes update
    blnUp1 = bnodes[lnUp1-1]
    Body[bln1-1:bln2] = []
    Body[blnUp1-1:blnUp1-1] = blines

    ###### go back to Tree
    blnShow = blnUp1
    vim.command("call Voom_OopFromBody(%s,%s,%s,'noa')" %(body,tree, blnShow))

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### tree lines to move; levels in VOOM.levels to move
    tlines = Tree[ln1-1:ln2]
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        tlines = [changeLevTreeHead(h, levDelta) for h in tlines]
        nLevels = [(lev+levDelta) for lev in nLevels]
    #print '-'*10; print '\n'.join(tlines)

    ### move tree lines; update VOOM.levels
    # cut, then insert
    Tree[ln1-1:ln2] = []
    Tree[lnUp1-1:lnUp1-1] = tlines
    levels[ln1-1:ln2] = []
    levels[lnUp1-1:lnUp1-1] = nLevels

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VOOM.snLns[body] = lnUp1

    ###update bnodes
    # increment lnums in the range before which the move is made
    delta = bln2-bln1+1
    for i in xrange(lnUp1-1,ln1-1):
        bnodes[i]+=delta
    # decrement lnums in the range which is being moved
    delta = bln1-blnUp1
    for i in xrange(ln1-1,ln2):
        bnodes[i]-=delta
    # cut, insert
    nLines = bnodes[ln1-1:ln2]
    bnodes[ln1-1:ln2] = []
    bnodes[lnUp1-1:lnUp1-1] = nLines

    # we don't get here only if previous code fails
    vim.command('let l:blnShow=%s' %blnShow)

#  ..............
#  .............. blnUp1-1
#  ============== blnUp1=bnodes[lnUp1-1]
#  range before
#  which to move
#  ..............
#  ============== bln1=bnodes[ln1-1]
#  range being
#  moved
#  .............. bln2=bnodes[ln2]-1, can be last line
#  ==============
#  ..............


def voom_OopDown(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnDn1, lnDn1_status = int(vim.eval('l:lnDn1')), vim.eval('l:lnDn1_status')
    # note: lnDn1 == ln2+1
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    ### compute change in level, and line after which to insert
    # current level
    levOld = levels[ln1-1]
    # new level is either that of lnDn1 or +1
    levNew = levels[lnDn1-1]
    # line afer which to insert
    lnIns = lnDn1
    if lnDn1==len(levels): # end of Tree
        pass
    # lnDn1 has children; insert as child unless it's folded
    elif levels[lnDn1-1] < levels[lnDn1]:
        if lnDn1_status=='folded':
            lnIns += nodeSubnodes(body,lnDn1)
        else:
            levNew+=1
    levDelta = levNew-levOld

    ### body lines to move
    bln1 = bnodes[ln1-1]
    bln2 = bnodes[ln2]-1
    blines = Body[bln1-1:bln2]
    if levDelta:
        for bl in bnodes[ln1-1:ln2]:
            blines[bl-bln1] = changeLevBodyHead(blines[bl-bln1], levDelta, body)

    ### move body lines: insert, then cut
    if lnIns < len(bnodes): blnIns = bnodes[lnIns]-1
    else: blnIns = len(Body)
    Body[blnIns:blnIns] = blines
    Body[bln1-1:bln2] = []

    ###update bnodes
    # increment lnums in the range which is being moved
    delta = blnIns-bln2
    for i in xrange(ln1-1,ln2):
        bnodes[i]+=delta
    # decrement lnums in the range after which the move is made
    delta = bln2-bln1+1
    for i in xrange(ln2,lnIns):
        bnodes[i]-=delta
    # insert, cut
    nLines = bnodes[ln1-1:ln2]
    bnodes[lnIns:lnIns] = nLines
    bnodes[ln1-1:ln2] = []

    # compute and set new snLn
    snLn_ = VOOM.snLns[body]
    snLn = lnIns+1-(ln2-ln1+1)
    VOOM.snLns[body] = snLn
    vim.command('let snLn=%s' %snLn)

    ###### go back to Tree
    # must be done after bnodes update
    blnShow = bnodes[snLn-1]
    vim.command("call Voom_OopFromBody(%s,%s,%s,'noa')" %(body,tree, blnShow))

    ### remove snLn mark before doing anything with Tree lines
    Tree[snLn_-1] = ' ' + Tree[snLn_-1][1:]

    ### tree lines to move; levels to move
    tlines = Tree[ln1-1:ln2]
    if levDelta:
        tlines = [changeLevTreeHead(h, levDelta) for h in tlines]
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        nLevels = [(lev+levDelta) for lev in nLevels]

    ### move tree lines; update VOOM.levels
    # insert, then cut
    Tree[lnIns:lnIns] = tlines
    Tree[ln1-1:ln2] = []
    levels[lnIns:lnIns] = nLevels
    levels[ln1-1:ln2] = []

    ### add snLn mark
    Tree[snLn-1] = '=' + Tree[snLn-1][1:]

    # we don't get here only if previous code fails
    vim.command('let l:blnShow=%s' %blnShow)

#  ..............
#  ============== bln1=bnodes[ln1-1]
#  range being
#  moved
#  .............. bln2=bnodes[ln2]-1
#  ============== blnDn1=bnodes[lnDn1-1]
#  range after
#  which to move
#  .............. blnIns=bnodes[lnIns]-1 or last Body line
#  ==============


def voom_OopRight(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    ### Move right means increment level by 1 for all nodes in the range.

    # can't move right if ln1 node is child of previous node
    if levels[ln1-1] > levels[ln1-2]:
        vim.command("call Voom_OopFromBody(%s,%s,-1,'noa')" %(body,tree))
        return

    ### change level numbers in Body headlines
    for bln in bnodes[ln1-1:ln2]:
        bline = Body[bln-1]
        Body[bln-1] = changeLevBodyHead(bline, 1, body)

    ###### go back to Tree
    # new snLn will be set to ln1
    blnShow = bnodes[ln1-1]
    vim.command("let &fdm=fdm_b")
    vim.command("call Voom_OopFromBody(%s,%s,%s,'noa')" %(body,tree, blnShow))

    ### change levels of Tree lines, VOOM.levels
    tlines = Tree[ln1-1:ln2]
    tlines = [changeLevTreeHead(h, 1) for h in tlines]
    nLevels = levels[ln1-1:ln2]
    nLevels = [(lev+1) for lev in nLevels]
    Tree[ln1-1:ln2] = tlines
    levels[ln1-1:ln2] = nLevels

    ### set snLn to ln1
    snLn = VOOM.snLns[body]
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VOOM.snLns[body] = snLn

    # we don't get here if previous code fails
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopLeft(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    ### Move left means decrement level by 1 for all nodes in the range.

    # can't move left if at top level 1
    if levels[ln1-1]==1:
        vim.command("call Voom_OopFromBody(%s,%s,-1,'noa')" %(body,tree))
        return
    # can't move left if the range is not at the end of tree
    elif ln2!=len(levels) and levels[ln2]==levels[ln1-1]:
        vim.command("call Voom_OopFromBody(%s,%s,-1,'noa')" %(body,tree))
        return

    ### change level numbers in Body headlines
    for bln in bnodes[ln1-1:ln2]:
        bline = Body[bln-1]
        Body[bln-1] = changeLevBodyHead(bline, -1, body)

    ###### go back to Tree
    # new snLn will be set to ln1
    blnShow = bnodes[ln1-1]
    vim.command("let &fdm=fdm_b")
    vim.command("call Voom_OopFromBody(%s,%s,%s,'noa')" %(body,tree, blnShow))

    ### change levels of Tree lines, VOOM.levels
    tlines = Tree[ln1-1:ln2]
    tlines = [changeLevTreeHead(h, -1) for h in tlines]
    nLevels = levels[ln1-1:ln2]
    nLevels = [(lev-1) for lev in nLevels]
    Tree[ln1-1:ln2] = tlines
    levels[ln1-1:ln2] = nLevels

    ### set snLn to ln1
    snLn = VOOM.snLns[body]
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VOOM.snLns[body] = snLn

    # we don't get here if previous code fails
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopMark(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    marker_re = VOOM.markers_re.get(body, MARKER_RE)

    for i in xrange(ln1-1,ln2):
        # insert 'x' in Tree line
        tline = Tree[i]
        if tline[1]!='x':
            Tree[i] = '%sx%s' %(tline[0], tline[2:])
            # insert 'x' in Body headline
            bln = bnodes[i]
            bline = Body[bln-1]
            end = marker_re.search(bline).end(1)
            Body[bln-1] = '%sx%s' %(bline[:end], bline[end:])


def voom_OopUnmark(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    marker_re = VOOM.markers_re.get(body, MARKER_RE)

    for i in xrange(ln1-1,ln2):
        # remove 'x' from Tree line
        tline = Tree[i]
        if tline[1]=='x':
            Tree[i] = '%s %s' %(tline[0], tline[2:])
            # remove 'x' from Body headline
            bln = bnodes[i]
            bline = Body[bln-1]
            end = marker_re.search(bline).end(1)
            # remove one 'x', not enough
            #Body[bln-1] = '%s%s' %(bline[:end], bline[end+1:])
            # remove all consecutive 'x' chars
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('x'))


def voom_OopMarkSelected(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln = int(vim.eval('l:ln'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    marker_re = VOOM.markers_re.get(body, MARKER_RE)

    bln_selected = bnodes[ln-1]
    # remove '=' from all other Body headlines
    # also, strip 'x' and 'o' after removed '='
    for bln in bnodes[1:]:
        if bln==bln_selected: continue
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        bline2 = bline[end:]
        if not bline2: continue
        if bline2[0]=='=':
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('=xo'))
        elif bline2[0]=='o' and bline2[1:] and bline2[1]=='=':
            Body[bln-1] = '%s%s' %(bline[:end+1], bline[end+1:].lstrip('=xo'))

    # insert '=' in current Body headline, but only if it's not there already
    bline = Body[bln_selected-1]
    end = marker_re.search(bline).end()
    bline2 = bline[end:]
    if not bline2:
        Body[bln_selected-1] = '%s=' %bline
        return
    if bline2[0]=='=':
        return
    elif bline2[0]=='o' and bline2[1:] and bline2[1]=='=':
        return
    elif bline2[0]=='o':
        end+=1
    Body[bln_selected-1] = '%s=%s' %(bline[:end], bline[end:])


#--- Tree Folding Operations --- {{{2
# Opened/Closed Tree buffer folds are equivalent to Expanded/Contracted nodes.
# By default, folds are closed.
# Opened folds are marked by 'o' in Body headlines (after 'x', before '=').
#
# To determine which folds are currently closed/opened, we open all closed
# folds one by one, from top to bottom, starting from top level visible folds.
# This produces list of closed folds.
#
# To restore folding according to a list of closed folds:
#   open all folds;
#   close folds from bottom to top.
#
# Conventions:
#   cFolds --lnums of closed folds
#   oFolds --lnums of opened folds
#   ln, ln1, ln2  --Tree line number
#
# NOTE: Cursor position and window view are not restored here.


def voom_OopFolding(action): #{{{3
    body = int(vim.eval('l:body'))
    # check and adjust range lnums
    # don't worry about invalid range lnums: Vim checks that
    if not action=='cleanup':
        ln1, ln2 = int(vim.eval('a:ln1')), int(vim.eval('a:ln2'))
        if ln2<ln1: ln1,ln2=ln2,ln1 # probably redundant
        if ln2==1: return
        #if ln1==1: ln1=2
        if ln1==ln2:
            ln2 = ln2 + nodeSubnodes(body, ln2)
            if ln1==ln2: return

    if action=='save':
        cFolds = foldingGet(ln1, ln2)
        foldingWrite(ln1, ln2, cFolds, body)
    elif action=='restore':
        cFolds = foldingRead(ln1, ln2, body)
        foldingCreate(ln1, ln2, cFolds)
    elif action=='cleanup':
        foldingCleanup(body)


def foldingGet(ln1, ln2): #{{{3
    """Get all closed folds in line range ln1-ln2, including subfolds.
    If line ln2 is visible and is folded, its subfolds are included.
    """
    cFolds = []
    lnum = ln1
    # go through top level folded lines (visible closed folds)
    while lnum < ln2+1:
        # line lnum is first line of a closed fold
        if int(vim.eval('foldclosed(%s)' %lnum))==lnum:
            cFolds.append(lnum)
            # line after this fold and subfolds
            foldend = int(vim.eval('foldclosedend(%s)' %lnum))+1
            lnum0 = lnum
            lnum = foldend
            vim.command('keepj normal! %sGzo' %lnum0)
            # open every folded line in this fold
            for ln in xrange(lnum0+1, foldend):
                # line ln is first line of a closed fold
                if int(vim.eval('foldclosed(%s)' %ln))==ln:
                    cFolds.append(ln)
                    vim.command('keepj normal! %sGzo' %ln)
        else:
            lnum+=1

    cFolds.reverse()
    # close back opened folds
    for ln in cFolds:
        vim.command('keepj normal! %sGzc' %ln)
    return cFolds


def foldingFlip(ln1, ln2, folds, body): #{{{3
    """Convert list of opened/closed folds in range ln1-ln2 into list of
    closed/opened folds.
    """
    # This also eliminates lnums of nodes without children.
    folds = {}.fromkeys(folds)
    folds_flipped = []
    for ln in xrange(ln1,ln2+1):
        if nodeHasChildren(body, ln) and not ln in folds:
            folds_flipped.append(ln)
    folds_flipped.reverse()
    return folds_flipped


def foldingCreate(ln1, ln2, cFolds): #{{{3
    """Create folds in range ln1-ln2 from a list of closed folds in that range.
    The list must be reverse sorted.
    """
    #cFolds.sort()
    #cFolds.reverse()
    #vim.command('keepj normal! zR')
    vim.command('%s,%sfoldopen!' %(ln1,ln2))
    for ln in cFolds:
        vim.command('keepj normal! %sGzc' %ln)


def foldingRead(ln1, ln2, body): #{{{3
    """Read "o" marks in Body headlines."""
    cFolds = []
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    bnodes = VOOM.bnodes[body]
    Body = VOOM.buffers[body]

    for ln in xrange(ln1,ln2+1):
        if not nodeHasChildren(body, ln):
            continue
        bline = Body[bnodes[ln-1]-1]
        end = marker_re.search(bline).end()
        if end<len(bline) and bline[end]=='o':
            continue
        else:
            cFolds.append(ln)

    cFolds.reverse()
    return cFolds


def foldingWrite(ln1, ln2, cFolds, body): #{{{3
    """Write "o" marks in Body headlines."""
    cFolds = {}.fromkeys(cFolds)
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    bnodes = VOOM.bnodes[body]
    Body = VOOM.buffers[body]

    for ln in xrange(ln1,ln2+1):
        if not nodeHasChildren(body, ln):
            continue
        bln = bnodes[ln-1]
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        isClosed = ln in cFolds
        # headline is marked with 'o'
        if end<len(bline) and bline[end]=='o':
            # remove 'o' mark
            if isClosed:
                Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('ox'))
        # headline is not marked with 'o'
        else:
            # add 'o' mark
            if not isClosed:
                if end==len(bline):
                    Body[bln-1] = '%so' %bline
                elif bline[end] != 'o':
                    Body[bln-1] = '%so%s' %(bline[:end], bline[end:])


def foldingCleanup(body): #{{{3
    """Remove "o" marks from  from nodes without children."""
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    bnodes = VOOM.bnodes[body]
    Body = VOOM.buffers[body]

    for ln in xrange(2,len(bnodes)+1):
        if nodeHasChildren(body, ln): continue
        bln = bnodes[ln-1]
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        if end<len(bline) and bline[end]=='o':
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('ox'))


#--- Sort Operations --- {{{2
# 1) Sort siblings of the current node.
# - Get list of siblings of the current node (as Tree lnums).
#   Two nodes are siblings if they have the same parent and the same level.
# - Construct list of corresponding Tree headlines. Decorate with indexes and
#   Tree lnums. Sort by headline text.
# - Construct new Body region from nodes in sorted order. Replace the region.
#   IMPORTANT: this does not change outline data (Tree, VOOM.levels,
#   VOOM.bnodes) for nodes with smaller levels or for nodes outside of the
#   siblings region. Thus, recursive sort is possible.
#
# 2) Deep (recursive) sort: sort siblings of the current node and siblings in
# all subnodes. Sort as above for all groups of siblings in the affected
# region, starting from the most deeply nested.
# - Construct list of groups of all siblings: top to bottom, decorate each
#   siblings group with level and parent lnum.
# - Reverse sort the list by levels.
# - Do sort for each group of siblings in the list: from right to left and from
#   bottom to top.
#
# 3) We modify only the Body buffer. We then do global outline update to redraw
# the Tree and to update outline data. Performing targeted update as in other
# outline operations is too tedious.


def voom_OopSort(): #{{{3=
    # Returning before setting l:blnShow means no changes were made.
    # parse options
    oDeep = False
    D = {'oIgnorecase':0, 'oUnicode':0, 'oEnc':0, 'oReverse':0, 'oFlip':0, 'oShuffle':0}
    options = vim.eval('a:qargs')
    options = options.strip().split()
    for o in options:
        if o=='deep': oDeep = True
        elif o=='i':       D['oIgnorecase'] = 1
        elif o=='u':       D['oUnicode']    = 1
        elif o=='r':       D['oReverse']    = 1 # sort in reverse order
        elif o=='flip':    D['oFlip']       = 1 # reverse without sorting
        elif o=='shuffle': D['oShuffle']    = 1
        else:
            vim.command("call Voom_ErrorMsg('VOoM (VoomSort): invalid option: %s')" %o.replace("'","''"))
            vim.command("call Voom_WarningMsg('VOoM (VoomSort): valid options are: deep, i (ignore-case), u (unicode), r (reverse-sort), flip, shuffle')")
            return

    if (D['oReverse'] + D['oFlip'] + D['oShuffle']) > 1:
        vim.command("call Voom_ErrorMsg('VOoM (VoomSort): these options cannot be combined: r, flip, shuffle')")
        return

    if D['oShuffle']:
        global random
        if random is None: import random

    if D['oUnicode']:
        D['oEnc'] = getVimEnc()

    # get data
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln = int(vim.eval('l:ln'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]

    # Tree lnums of siblings of the current node
    siblings = nodeSiblings(body,ln)
    # progress flags: got >1 siblings, order changed after sort
    flag1,flag2 = 0,0
    ### do sorting
    if not oDeep:
        flag1,flag2 = sortSiblings(body, tree, siblings, **D)
    else:
        siblings_groups = getSiblingsGroups(body,siblings)
        for group in siblings_groups:
            m, n = sortSiblings(body, tree, group, **D)
            flag1+=m; flag2+=n

    if flag1==0:
        vim.command("call Voom_WarningMsg('VOoM (VoomSort): nothing to sort')")
        return
    elif flag2==0:
        vim.command("call Voom_WarningMsg('VOoM (VoomSort): already sorted')")
        return

    # Show first sibling. Tracking the current node and bnode is too hard.
    ln1 = siblings[0]
    ln2 = siblings[-1] + nodeSubnodes(body,siblings[-1])
    blnShow = bnodes[ln1-1]
    vim.command('let [l:blnShow,l:ln1,l:ln2]=[%s,%s,%s]' %(blnShow,ln1,ln2))


def sortSiblings(body, tree, siblings, oIgnorecase, oUnicode, oEnc, oReverse, oFlip, oShuffle): #{{{3
    """Sort sibling nodes. 'siblings' is list of Tree lnums in ascending order.
    This only modifies Body buffer. Outline data are not updated.
    Return progress flags (flag1,flag2), see voom_OopSort().
    """
    sibs = siblings
    if len(sibs) < 2:
        return (0,0)
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]
    z, Z = len(sibs), len(bnodes)

    ### decorate siblings for sorting
    # [(Tree headline text, index, lnum), ...]
    sibs_dec = []
    for i in xrange(z):
        sib = sibs[i]
        head = Tree[sib-1].split('|',1)[1]
        if oUnicode and oEnc:
            head = unicode(head, oEnc, 'replace')
        if oIgnorecase:
            head = head.lower()
        sibs_dec.append((head, i, sib))

    ### sort
    if oReverse:
        sibs_dec.sort(key=lambda x: x[0], reverse=True)
    elif oFlip:
        sibs_dec.reverse()
    elif oShuffle:
        random.shuffle(sibs_dec)
    else:
        sibs_dec.sort()

    sibs_sorted = [i[2] for i in sibs_dec]
    #print sibs_dec; print sibs_sorted
    if sibs==sibs_sorted:
        return (1,0)

    ### blnum1, blnum2: first and last Body lnums of the affected region
    blnum1 = bnodes[sibs[0]-1]
    n = sibs[-1] + nodeSubnodes(body,sibs[-1])
    if n < Z:
        blnum2 = bnodes[n]-1
    else:
        blnum2 = len(Body)

    ### construct new Body region
    blines = []
    for i in xrange(z):
        sib = sibs[i]
        j = sibs_dec[i][1] # index into sibs that points to new sib
        sib_new = sibs[j]

        # get Body region for sib_new branch
        bln1 = bnodes[sib_new-1]
        if j+1 < z:
            sib_next = sibs[j+1]
            bln2 = bnodes[sib_next-1]-1
        else:
            node_last = sib_new + nodeSubnodes(body,sib_new)
            if node_last < Z:
                bln2 = bnodes[node_last]-1
            else:
                bln2 = len(Body)

        blines.extend(Body[bln1-1:bln2])

    ### replace Body region with the new, sorted region
    body_len = len(Body)
    Body[blnum1-1:blnum2] = blines
    assert body_len == len(Body)

    return (1,1)


#---EXECUTE SCRIPT----------------------------{{{1
#

def voom_GetBodyLines(): #{{{2
    body = int(vim.eval('l:body'))
    ln1 = int(vim.eval('a:lnum'))

    vim.command('let nodeStart=%s' %(VOOM.bnodes[body][ln1-1]) )

    ln2 = ln1 + nodeSubnodes(body, ln1)
    if ln2==len(VOOM.bnodes[body]): # last line
        vim.command('let nodeEnd="$"')
    else:
        nodeEnd = VOOM.bnodes[body][ln2]-1
        vim.command('let nodeEnd=%s' %nodeEnd )
    # (nodeStart,nodeEnd) can be (1,0), see voom_TreeSelect()
    # it doesn't matter here


def voom_GetBodyLines1(): #{{{2

    buftype = vim.eval('l:buftype')
    body = int(vim.eval('l:body'))
    lnum = int(vim.eval('l:lnum'))
    if buftype=='body':
        lnum = bisect.bisect_right(VOOM.bnodes[body], lnum)

    bln1 =  VOOM.bnodes[body][lnum-1]
    vim.command("let l:bln1=%s" %bln1)

    if lnum==len(VOOM.bnodes[body]):
        # last node
        vim.command("let l:bln2='$'")
    else:
        bln2 =  VOOM.bnodes[body][lnum]-1 or 1
        vim.command("let l:bln2=%s" %bln2)


def execScript(): #{{{2
    """Execute script file."""
    #sys.path.insert(0, voom_dir)
    try:
        #d = {'vim':vim, 'VOOM':VOOM, 'voom':sys.modules[__name__]}
        d = { 'vim':vim, 'VOOM':VOOM, 'voom':sys.modules['voom'] }
        execfile(voom_script, d)
        print '---end of Python script---'
    except Exception:
        typ,val,tb = sys.exc_info()
        lines = traceback.format_exception(typ,val,tb)
        print ''.join(lines)
    #del sys.path[0]


#---LOG BUFFER--------------------------------{{{1
#
class LogBufferClass: #{{{2
    """A file-like object for replacing sys.stdout and sys.stdin with a Vim buffer."""
    def __init__(self): #{{{3
        self.buffer = vim.current.buffer
        self.logbnr = vim.eval('bufnr("")')
        self.buffer[0] = 'Python Log buffer ...'
        #self.encoding = vim.eval('&enc')
        self.encoding = getVimEnc()
        self.join = False

    def write(self,s): #{{{3
        """Append string to buffer, scroll Log windows in all tabs."""
        # Messages are terminated by sending '\n' (null string? ^@).
        # Thus "print '\n'" sends '\n' twice.
        # The message itself can contain '\n's.
        # One line can be sent in many strings which don't always end with \n.
        # This is certainly true for Python errors and for 'print a, b, ...' .

        # Can't append unicode strings. This produces an error:
        #  :py vim.current.buffer.append(u'test')

        # Can't have '\n' in appended list items, so always use splitlines().
        # A trailing \n is lost after splitlines(), but not for '\n\n' etc.
        #print self.buffer.name

        if not s: return
        # Nasty things happen when printing to unloaded PyLog buffer.
        # This also catches printing to noexisting buffer, as in pydoc help() glitch.
        if vim.eval("bufloaded(%s)" %self.logbnr)=='0':
            vim.command("echoerr 'VOoM (PyLog): PyLog buffer %s is unloaded or doesn''t exist'" %self.logbnr)
            vim.command("echoerr 'VOoM (PyLog): unable to write string:'")
            vim.command("echom '%s'" %(repr(s).replace("'", "''")) )
            vim.command("echoerr 'VOoM (PyLog): please try executing command Voomlog to fix'")
            return

        try:
            if type(s) == type(u" "):
                s = s.encode(self.encoding)

            # Join with previous message if it had no ending newline.
            if self.join==True:
                s = self.buffer[-1] + s
                del self.buffer[-1]

            if s[-1]=='\n':
                self.join = False
            else:
                self.join = True

            self.buffer.append(s.splitlines())
        except:
            typ,val,tb = sys.exc_info()
            lines1 = traceback.format_exception(typ,val,tb) # items can contain newlines
            lines2 = []
            for line in lines1:
                lines2+=line.splitlines()
            self.buffer.append('')
            self.buffer.append('VOoM: exception writing to PyLog buffer:')
            self.buffer.append(repr(s))
            self.buffer.append(lines2)
            self.buffer.append('')

        vim.command('call Voom_LogScroll()')


#---misc--------------------------------------{{{1

def getVimEnc(): #{{{2
    """Get Vim internal encoding."""
    # When &enc is one of these Vim allegedly uses utf-8 internally.
    # See |encoding|, mbyte.c, values are from |encoding-values|
    d = {'ucs-2':0, 'ucs-2le':0, 'utf-16':0, 'utf-16le':0, 'ucs-4':0, 'ucs-4le':0}
    enc = vim.eval('&enc')
    if enc in d:
        return 'utf-8'
    else:
        return enc


# modelines {{{1
# vim:fdm=marker:fdl=0:
# vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart):
