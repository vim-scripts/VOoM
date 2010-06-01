" This VOoM add-on shows how to customize Tree headline text for individual
" Body filetypes.
" Important: This file must be sourced after entire voom.vim has been sourced.
" Use option g:voom_user_command as explained in |voom_addons|.
" Example: Move this file to $HOME/.vim/voom_add-ons/
" and add the following line to .vimrc:
"   let g:voom_user_command = "runtime! voom_add-ons/*.vim"


" Alternative to defining dictionary g:voom_rstrip_chars in vimrc: add entries
" for filetypes of interest. Note that Space and Tab must be included.
if 0
    let g:voom_rstrip_chars["autohotkey"] = "; \t"
endif


python << EOF

# Replace default headline construction procedure with a custom function:
# 1. Define a make_head Python function.
#       - It returns a string: Tree headline text.
#       - It requires two arguments: bline and match.
#           - bline is Body line from which we make Tree headline.
#           - match is MatchObject produced by re.search() for bline and fold
#             marker regex
#               - bline[:match.start()] gives part of Body line before the
#                 matching fold marker. This is what we usually start from.
# 2. Register function in dictionary voom.MAKE_HEAD for filetypes with which
#    it should be used.

import re

if 1:
    # HTML headline: like default plus delete all html tags
    html_tag_sub = re.compile('<.*?>').sub
    def voom_make_head_html(bline,match):
        s = bline[:match.start()].strip().strip('-=~').strip()
        s = html_tag_sub('',s)
        if s.endswith('<!'):
            return s[:-2].strip()
        else:
            return s
    voom.MAKE_HEAD['html'] = voom_make_head_html

if 0:
    # Python headline: like default plus remove "def "
    def voom_make_head_python(bline,match):
        s = bline[:match.start()].lstrip().rstrip('# \t').strip('-=~').strip()
        if s.startswith('def ') or s.startswith('def\t'):
            return s[3:].lstrip()
        else:
            return s
    voom.MAKE_HEAD['python'] = voom_make_head_python
    #voom.MAKE_HEAD['ruby'] = voom_make_head_python

if 0:
    # Vim headline: like default plus remove leading "fu ", "fun ", ..., "function ".
    vim_func_sub = re.compile(r"^fu(n|nc|nct|ncti|nctio|nction)?!?\s+").sub
    def voom_make_head_vim(bline,match):
        s = bline[:match.start()].lstrip().rstrip('" \t').strip('-=~').strip()
        s = vim_func_sub('',s)
        return s
    voom.MAKE_HEAD['vim'] = voom_make_head_vim

EOF

