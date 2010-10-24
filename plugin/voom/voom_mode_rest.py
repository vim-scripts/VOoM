# voom_mode_rest.py
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
VOoM markup mode for reStructuredText, see |voom_mode_rest|.
http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.html#sections
    The following are all valid section title adornment characters:
    ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~

    Some characters are more suitable than others. The following are recommended:
    = - ` : . ' " ~ ^ _ * + #

http://docs.python.org/documenting/rest.html#sections
Python recommended styles:   ##  **  =  -  ^  "
"""
try:
    import vim
    ENC = vim.eval('&enc')
    if ENC in ['utf-8', 'ucs-2', 'ucs-2le', 'utf-16', 'utf-16le', 'ucs-4', 'ucs-4le']:
        ENC = 'utf-8'
except ImportError:
    ENC = 'utf-8'

# All valid section title adornment characters.
AD_CHARS = """  ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~  """
AD_CHARS = AD_CHARS.split()

# List of adornment styles, in order of preference.
# Adornment style (ad) is a char or double char: '=', '==', '-', '--', '*', etc.
# Char is adornment char, double if there is overline.
AD_STYLES = """  ==  --  =  -  *  "  '  `  ~  :  ^  +  #  .  _  """
AD_STYLES = AD_STYLES.split()

# add all other possible styles to AD_STYLES
d = {}.fromkeys(AD_STYLES)
for c in AD_CHARS:
    if not c*2 in d:
        AD_STYLES.append(c*2)
    if not c in d:
        AD_STYLES.append(c)
assert len(AD_STYLES)==64

# convert AD_CHARS to dict for faster lookups
AD_CHARS = {}.fromkeys(AD_CHARS)


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for list of Body lines.
    blines can also be Vim buffer object.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append

    # {adornment style: level, ...}
    # Level indicates when the first instance of this style was found.
    ads_levels = {}

    # diagram of Body lines when a headline is detected
    # trailing whitespace always removed with rstrip()
    # a b c
    # ------ L3, blines[i-2] -- an overline or blank line
    #  head  L2, blines[i-1] -- title line, not blank, <= than underline, can be inset only if overline
    # ------ L1, blines[i]   -- current line, always underline
    # x y z
    L1, L2, L3 = '','',''

    gotHead = None
    for i in xrange(Z):
        L2, L3 = L1, L2
        L1 = blines[i].rstrip()
        # current line must be undereline and title line cannot be blank
        if not (L1 and L2 and (L1[0] in AD_CHARS) and L1.lstrip(L1[0])==''):
            continue
        # underline must be as long as headline text
        if len(L1) < len(L2.decode(ENC,'replace')):
            continue
        # there is no overline; L3 must be blank line; L2 must be not inset
        if not L3 and len(L2)==len(L2.lstrip()):
            #if len(L2) <= len(L1):
            gotHead = True
            ad = L1[0]
            head = L2.strip()
            bnode = i
        # there is overline -- bnode is lnum of overline!
        elif L3==L1:
            #if len(L2) <= len(L1):
            gotHead = True
            ad = L1[0]*2
            head = L2.strip()
            bnode = i-1

        if gotHead:
            if not ad in ads_levels:
                ads_levels[ad] = len(ads_levels)+1
            lev = ads_levels[ad]
            gotHead = None
            L1, L2, L3 = '','',''

            tline = '  %s|%s' %('. '*(lev-1), head)
            tlines_add(tline)
            bnodes_add(bnode)
            levels_add(lev)

    # save ads_levels for outline operations
    # don't clobber VO.ads_levels when parsing clipboard during Paste
    # which is the only time blines is not Body
    if blines is VO.Body:
        VO.ads_levels = ads_levels

    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines, column).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    column is cursor position in new headline in Body buffer.
    """
    tree_head = 'NewHeadline'
    column = 1
    ads_levels = VO.ads_levels
    levels_ads = dict([[v,k] for k,v in ads_levels.items()])

    ad = get_adornment(levels_ads, ads_levels, level)

    if len(ad)==1:
        bodyLines = ['NewHeadline', ad*11, '']
    elif len(ad)==2:
        ad = ad[0]
        bodyLines = [ad*11, 'NewHeadline', ad*11, '']

    # Add blank line when Body line after which inserting is not blank.
    if VO.Body[blnum-1].strip():
        bodyLines[0:0] = ['']

    return (tree_head, bodyLines, column)


#def hook_changeLevBodyHead(VO, h, levDelta):
#    """Increase of decrease level number of Body headline by levDelta."""
#    if levDelta==0: return h
#    return h


def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    #print oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, tlnumCut, blnumCut
    Body = VO.Body
    Z = len(Body)
    bnodes, levels = VO.bnodes, VO.levels

    # blnum1 blnum2 is first and last lnums of Body region pasted, inserted
    # during up/down, or promoted/demoted.
    if blnum1:
        assert blnum1 == bnodes[tlnum1-1]
        if tlnum2 < len(bnodes):
            assert blnum2 == bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # blnumCut is Body lnum after which a region was removed during 'cut',
    # 'up', 'down'. We need to check if there is blank line between nodes
    # used to be separated by the cut/moved region to prevent headline loss.
    if blnumCut:
        if tlnumCut < len(bnodes):
            assert blnumCut == bnodes[tlnumCut]-1
        else:
            assert blnumCut == Z

    # Total number of added lines minus number of deleted lines.
    b_delta = 0

    ### After 'cut' or 'up': insert blank line if there is none
    # between the nodes used to be separated by the cut/moved region.
    if (oop=='cut' or oop=='up') and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
        Body[blnumCut:blnumCut] = ['']
        update_bnodes(VO, tlnumCut+1 ,1)
        b_delta+=1

    if oop=='cut':
        return

    ### Prevent loss of headline after last node in the region:
    # insert blank line after blnum2 if blnum2 is not blank, that is insert
    # blank line before bnode at tlnum2+1.
    if blnum2 < Z and Body[blnum2-1].strip():
        Body[blnum2:blnum2] = ['']
        update_bnodes(VO, tlnum2+1 ,1)
        b_delta+=1

    ### Adjust levels of headlines in the affected region.
    # Have to do this after Paste even if level is unchanged -- adornments can
    # be different when pasting from other outlines.
    # Examine each headline, from bottom to top, and change adornment style.
    # To change from underline to overline style:
    #   insert overline.
    # To change from overline to underline style:
    #   delete overline if there is blank before it;
    #   otherwise change overline to blank line;
    #   remove inset from headline text.
    # Update bnodes after inserting or deleting a line.
    if levDelta or oop=='paste':
        ads_levels = VO.ads_levels
        levels_ads = dict([[v,k] for k,v in ads_levels.items()])
        levels_ads_ = {}
        for i in xrange(tlnum2, tlnum1-1, -1):
            # required level (VO.levels has been updated)
            lev = levels[i-1]
            # required adornment style
            ad = levels_ads_.get(lev, None)
            if not ad:
                ad = get_adornment(levels_ads, ads_levels, lev)
                levels_ads_[lev] = ad

            # deduce current adornment style
            bln = bnodes[i-1]
            L1 = Body[bln-1].rstrip()
            L2 = Body[bln].rstrip()
            if bln+1 < len(Body):
                L3 = Body[bln+1].rstrip()
            else:
                L3 = ''
            ad_ = deduce_ad_style(L1,L2,L3)

            # change adornment style
            # see deduce_ad_style() for diagram
            if ad_==ad:
                continue
            elif len(ad_)==1 and len(ad)==1:
                Body[bln] = ad*len(L2)
            elif len(ad_)==2 and len(ad)==2:
                Body[bln-1] = ad[0]*len(L1)
                Body[bln+1] = ad[0]*len(L3)
            elif len(ad_)==1 and len(ad)==2:
                # change underline if different
                if not ad_ == ad[0]:
                    Body[bln] = ad[0]*len(L2)
                # insert overline; current bnode doesn't change
                Body[bln-1:bln-1] = [ad[0]*len(L2)]
                update_bnodes(VO, i+1, 1)
                b_delta+=1
            elif len(ad_)==2 and len(ad)==1:
                # change underline if different
                if not ad_[0] == ad:
                    Body[bln+1] = ad*len(L3)
                # remove headline inset if any
                if not len(L2) == len(L2.lstrip()):
                    Body[bln] = L2.lstrip()
                # check if line before overline is blank
                if bln >1:
                    L0 = Body[bln-2].rstrip()
                else:
                    L0 = ''
                # there is blank before overline
                # delete overline; current bnode doesn't change
                if not L0:
                    Body[bln-1:bln] = []
                    update_bnodes(VO, i+1, -1)
                    b_delta-=1
                # there is no blank before overline
                # change overline to blank; only current bnode needs updating
                else:
                    Body[bln-1] = ''
                    bnodes[i-1]+=1

    ### Prevent loss of first headline: make sure it is preceded by a blank line
    blnum1 = bnodes[tlnum1-1]
    if blnum1 > 1 and Body[blnum1-2].strip():
        Body[blnum1-1:blnum1-1] = ['']
        update_bnodes(VO, tlnum1 ,1)
        b_delta+=1

    ### After 'down' : insert blank line if there is none
    # between the nodes used to be separated by the moved region.
    if oop=='down' and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
        Body[blnumCut:blnumCut] = ['']
        update_bnodes(VO, tlnumCut+1 ,1)
        b_delta+=1

    assert len(Body) == Z + b_delta


def update_bnodes(VO, tlnum, delta):
    """Update VO.bnodes by adding/substracting delta to each bnode
    starting with bnode at tlnum and to the end.
    """
    bnodes = VO.bnodes
    for i in xrange(tlnum, len(bnodes)+1):
        bnodes[i-1] += delta


def get_adornment(levels_ads, ads_levels, level):
    """Return adornment style for given level."""
    if level in levels_ads:
        ad = levels_ads[level]
    else:
        ad = None
        for s in AD_STYLES:
            if not s in ads_levels:
                ad = s
                break
    return ad or levels_ads[len(levels_ads)]


def deduce_ad_style(L1,L2,L3):
    """Deduce adornment style given first 3 lines of Body node.
    1st line is headline, that is bnode line.
    """
    # '--' style    '-' style
    #
    #       L0            L0             Body[bln-2]
    # ----  L1      head  L1   <--bnode  Body[bln-1]
    # head  L2      ----  L2             Body[bln]
    # ----  L3      text  L3             Body[bln+1]

    # bnode is overline
    if L1==L3 and (L1[0] in AD_CHARS) and L1.lstrip(L1[0])=='' and (len(L1) >= len(L2.decode(ENC,'replace'))):
        ad_ = 2*L1[0]
    # bnode is headline text
    elif (L2[0] in AD_CHARS) and L2.lstrip(L2[0])=='' and (len(L2) >= len(L1.decode(ENC,'replace'))):
        ad_ = L2[0]
    else:
        print L1
        print L2
        print L3
        print ENC
        assert None

    return ad_

    # wrong if perverse headline like this (correct ad style is '-')
    #
    # ^^^^^
    # -----
    # ^^^^^
    # text


def deduce_ad_style_test(VO):
    """ Test to verify deduce_ad_style(). Execute from Vim
      :py voom.VOOMS[1].mmode.deduce_ad_style_test(voom.VOOMS[1])
    """
    bnodes, levels, Body = VO.bnodes, VO.levels, VO.Body
    ads_levels = VO.ads_levels
    levels_ads = dict([[v,k] for k,v in ads_levels.items()])

    for i in xrange(2, len(bnodes)+1):
        bln = bnodes[i-1]
        L1 = Body[bln-1].rstrip()
        L2 = Body[bln].rstrip()
        if bln+1 < len(Body):
            L3 = Body[bln+1].rstrip()
        else:
            L3 = ''
        ad = deduce_ad_style(L1,L2,L3)
        lev = levels[i-1]
        print i, ad, levels_ads[lev]
        assert ad == levels_ads[lev]


