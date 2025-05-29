if exists("g:loaded_vimhow")
   finish
endif
let g:loaded_vimhow = 1

python3 << EOF
# Imports Python modules to be used by the plugin.
import queue
import sys
import threading

def safe_import(module_names):
  for module_name in module_names:
    try:
        __import__(module_name)
        return True
    except ImportError:
        print(f"Warning: can't import {module_name}")
        return False

def append_to_sys_path(paths: list[str]):
  for path in paths:
    evaled_path = vim.eval(f"expand('{path}')")
    sys.path.append(evaled_path)

append_to_sys_path(
  [
    '~/.vim/bundle/vimhow/autoload/', 
    '/Users/marcbaechinger/monolit/code/vimhow/.venv/lib/python3.13/site-packages',  
  ]
)
imports_found = safe_import(["google.genai", "tutor"])
from tutor import VimTutor
from api_key import get_api_key

api_key = get_api_key()
has_tutor = imports_found and api_key is not None

callbackQueue = queue.Queue()

if not imports_found:
  print("imports not available")
elif api_key is None:
  print("please provide and api key")
else:
  system_instruction = (
      "You are an expert vim tutor."
      "You give clear an concise advise on how to use vim."
      "Your output are vim commands or vimscript function that help the user to edit text with vim."
      "Start with the sequence of commands or the functions and then explain step by step how the user can achieve the declared goal."
      "Format your output in markdown format"
      "Lines must not exeed 80 characters."
  )
  tutor = VimTutor(api_key, system_instruction)

def setNavigationInfo(index):
  size = len(tutor.history.entries)
  navigationInfo = f"({index + 1}/{size})"
  vim.command(f"let g:VimHowNavigationInfo = '{navigationInfo}'")
  return navigationInfo

def prompt():
  prompt = vim.vars['VimHowValue']
  if prompt is not None:
    index, historyItem = tutor.prompt(prompt.decode('utf-8'))
    setNavigationInfo(index)
    return tutor.get_last_response()
  else:
    return "no prompt found in g:VimHowValue"

def promptCallback():
  index, historyItem = tutor.get_last()
  setNavigationInfo(index)
  vim.command("call VimHowFetchResponse()");

def promptBlocking(prompt):
  tutor.prompt(prompt.decode('utf-8'))
  promptCallback()

def startPrompAsync():
  prompt = vim.vars['VimHowValue']
  thread = threading.Thread(
      target=promptBlocking,
      args = (prompt,)
  )
  thread.daemon = True 
  thread.start()
  return ""

def selectAndReturnPreviousResponse():
  prev = tutor.select_previous()
  if prev is None:
    return ""
  size = len(tutor.history.entries)
  navigationInfo = setNavigationInfo(prev[0])
  header = f"# -- {navigationInfo} in history --\n"
  historyItem = prev[1]
  return header + historyItem.response

def selectAndReturnNextResponse():
  nextItem = tutor.select_next()
  if nextItem is None:
    return "" 
  size = len(tutor.history.entries)
  index = nextItem[0]
  navigationInfo = setNavigationInfo(index)
  header = f"# -- {navigationInfo} in history --\n" if index < size else ""
  historyItem = nextItem[1]
  return header + historyItem.response

def getTotalTokenStats():
  if not has_tutor:
    return "0/0"
  return str(tutor.get_prompt_token_count()) + "/" + str(tutor.get_candidates_token_count())

def getSelectedTokenStats():
  if not has_tutor:
    return "-/-"
  _ , historyEvent = tutor.get_selected()
  if historyEvent is not None:
    return str(historyEvent.prompt_token_count) + "/" + str(historyEvent.candidates_token_count)
  else:
    return "-/-"

EOF

let s:promptBufferName = expand('~') . '/.vimhow/prompt.vimhow'
let s:responseBufferName = expand('~') . '/.vimhow/response.md'
let s:window_counter = 1
let s:readOnlyMarker = "^>"
let s:vimHowStatusDefault = "Enter prompt."
let s:vimHowStatusEditing = "Leave normal mode."
let s:vimHowStatusEdited = "Press ? to prompt."
let s:vimHowStatusThinking = "Sent prompt. Thinking..."
let s:vimHowStatusResponded = "Response written."
let s:vimHowThinking = 0

let g:VimHowStatus = "Not yet started"
let g:VimHowTotalTokenStats = "[-/-]"
let g:VimHowSelectedTokenStats = "[-/-]"
let g:VimHowNavigationInfo = ""

function! s:setVimHowStatus(status)
  let g:VimHowStatus = a:status
endfunction

function! s:getTotalTokenStats()
  let g:VimHowTotalTokenStats = py3eval('getTotalTokenStats()')
endfunction

function! s:getSelectedTokenStats()
  let g:VimHowSelectedTokenStats = py3eval('getSelectedTokenStats()')
endfunction

call s:getTotalTokenStats()
call s:getSelectedTokenStats()

function! s:appendToPrompt(text, markAsReadOnly)
  let winid = s:getPromptWinId()
  if winid != -1
    let lastLine = line('$', winid)
    let bufname = bufname(t:promptBufferNr)
    call appendbufline(bufname, lastLine, a:text) 
    let insertion_end = line('$', winid)
    if a:markAsReadOnly
      call s:markLinesReadOnly(lastLine, lastLine + 1, bufname)
    endif
  endif
endfunction

function! s:askAgent(prompt)
  let g:VimHowValue = trim(a:prompt)
  let nothing = py3eval('startPrompAsync()')
  call s:setVimHowStatus(s:vimHowStatusThinking)
  let s:vimHowThinking = 1
endfunction

function! VimHowFetchResponse()
  let s:vimHowThinking = 0
  let code = py3eval('tutor.get_last_response()')
  call s:renderResponse(code) 
  call s:getSelectedTokenStats()
  call s:setVimHowStatus(s:vimHowStatusResponded . " ->")
  call s:getTotalTokenStats()
  redraw!
endfunction

function! s:renderResponse(code)
  let winid = s:getResponseWinId()
  if winid != -1
    let lastLine = line('$', winid)
    let bufname = bufname(t:responseBufferNr)
    call deletebufline(bufname, 1, lastLine)
    call appendbufline(bufname, 1, split(a:code, "\n", 1)) 
  endif
endfunction

function! s:markLinesReadOnly(start_line, end_line, bufname)
  let lnum = a:start_line
  while lnum <= a:end_line
    let lines = getbufline(a:bufname, lnum, lnum + 1)
    if !empty(lines)
      let line_text = lines[0]
      if line_text !~# s:readOnlyMarker
        call setbufline(a:bufname, lnum, '> ' . line_text)
      endif
    endif
    let lnum = lnum + 1
  endwhile
endfunction

function! s:togglePrompt()
  call s:ensureDirectoryExists(expand('~') . '/.vimhow')
  if !exists("t:promptBufferNr")
    let t:windowId = s:window_counter
    let t:promptBufferNr = 0
    let t:responseBufferNr = 0
    let s:window_counter = s:window_counter + 1
    call s:setVimHowStatus(s:vimHowStatusDefault)
  endif
  if t:promptBufferNr && bufexists(s:promptBufferName)
    execute 'bd!' t:promptBufferNr
    execute 'bd!' t:responseBufferNr
    let t:promptBufferNr = 0
    let t:responseBufferNr = 0
  else
    let old_splitright = &splitright
    set splitright
    execute "vsplit" s:responseBufferName
    setlocal bufhidden=hide
    setlocal buftype=nofile
    setlocal nobuflisted
    setlocal noswapfile
    execute "split" s:promptBufferName
    resize 6
    vert resize 86
    setlocal bufhidden=hide
    setlocal nobuflisted
    setlocal noswapfile
    let t:promptBufferNr = bufnr(s:promptBufferName)
    let t:responseBufferNr = bufnr(s:responseBufferName)
    let &splitright = old_splitright
    silent! execute '$'
    normal! ^
  endif
endfunction

function! s:how(query)
    if trim(a:query) ==# ""
      echomsg "Empty prompt"
      call s:setVimHowStatus(s:vimHowStatusDefault)
      return
    endif
    let g:VimHowStatus = "Asking tutor..."
    call s:askAgent(a:query)
endfunction

function! s:prompt(bufname)
  let winId = s:getPromptWinId()
  let prompt = ""
  if winId != -1
    let lastLineNr = line('$', winId)
    let lines = getbufline(a:bufname, 1, lastLineNr)
    let filteredLines = filter(lines, 'v:val !~# "^>"')
    if len(filteredLines) < 1
      echomsg "Empty prompt"
      call s:setVimHowStatus(s:vimHowStatusDefault)
      return
    endif
    let prompt = join(filteredLines, "\n")
    call s:markLinesReadOnly(0, lastLineNr, s:promptBufferName)
    let g:VimHowStatus = "Asking tutor..."
    write
    call s:askAgent(prompt)
  endif
endfunction

function! s:displayPrevious()
  let response = py3eval('selectAndReturnPreviousResponse()')
  if response ==# ''
    echo "Already at the end of the history"
  else
    call s:renderResponse(response)
    call s:getSelectedTokenStats()
  endif
endfunction

function! s:displayNext()
  let response = py3eval('selectAndReturnNextResponse()')
  if response ==# ''
    echo "Already at the actual output"
  else
    call s:renderResponse(response)
    call s:getSelectedTokenStats()
  endif
endfunction

function! s:popupPrompt()
  let lNum = line('.')
  let prompt = trim(py3eval('tutor.get_selected_prompt()'))
  call setreg("*", prompt)
  let options = #{line: 0, col: 0, title:' Last prompt', time:10000, maxwidth:72, close:'click'}
  call popup_notification(split(prompt, "\n", 1), options)
endfunction

function s:hasPrompt()
  if t:promptBufferNr
    for line in getbufline(s:promptBufferName, 1, '$')
      if line !~# '^>'
        return 1
      endif
    endfor
  endif
  return 0
endfunction

function! s:setVimHowStatusAfterEditing()
  if s:vimHowThinking
    return
  endif
  if s:hasPrompt() == 1
    call s:setVimHowStatus(s:vimHowStatusEdited)
  else
    call s:setVimHowStatus(s:vimHowStatusDefault)
  endif
endfunction

" UI functions

function! s:getPromptWinId()
  if !t:promptBufferNr
    return -1
  endif
  let winids = win_findbuf(t:promptBufferNr)
  if !empty(winids)
    return winids[0]
  endif
  return -1
endfunction

function! s:getResponseWinId()
  if !t:responseBufferNr
    return -1
  endif
  let winids = win_findbuf(t:responseBufferNr)
  if !empty(winids)
    return winids[0]
  endif
  return -1
endfunction

" utility functions

function! s:ensureDirectoryExists(directory_path)
  if !isdirectory(a:directory_path)
    silent! call mkdir(a:directory_path, "p")
    if !isdirectory(a:directory_path)
      return 0 
    endif
  endif
  return 1 
endfunction

function! s:urlEncode(str)
  let encoded = substitute(a:str, '[^A-Za-z0-9_.-~]', '\=%02X', 'g')
  return encoded
endfunction

function! s:escape(string)
  let escapedString = substitute(a:string, '\\', '\\\\', 'g')
  let escapedString = substitute(escapedString, "'", "\\'", 'g')
  return substitute(escapedString, '\n', '\\n', 'g')
endfunction

" define auto commands

if !exists(":VimHowTogglePrompt")
  command -nargs=0  VimHowTogglePrompt :call s:togglePrompt()
  command -nargs=0  VimHowPrompt :call s:prompt(s:promptBufferName)
  command -nargs=1  VimHow :call s:how(<args>)
  command -nargs=0  VimHowSelectPrevious :call s:displayPrevious()
  command -nargs=0  VimHowSelectNext :call s:displayNext()
  command -nargs=0  VimHowPopupPrompt :call s:popupPrompt()
endif

augroup VimHowAutoCommands
  au! BufRead,BufNewFile *.vimhow set filetype=vimhow
  au! BufEnter,BufLeave *.vimhow :call s:setVimHowStatus(s:vimHowStatusDefault)
  au! InsertEnter *.vimhow :call s:setVimHowStatus(s:vimHowStatusEditing)
  au! InsertLeave,TextChanged *.vimhow :call s:setVimHowStatusAfterEditing()
augroup END

augroup VimHowMappings
  autocmd!
  autocmd FileType vimhow nnoremap <buffer> ? :VimHowPrompt<CR>
  autocmd FileType vimhow nnoremap <buffer> <S-F9> :VimHowPopupPrompt<CR>
  autocmd FileType vimhow nnoremap <buffer> <S-Left> :VimHowSelectPrevious<CR>
  autocmd FileType vimhow nnoremap <buffer> <S-Right> :VimHowSelectNext<CR>
  autocmd FileType vimhow nnoremap <buffer> C :%d _<CR>
augroup END

nnoremap <silent> <S-F6> :VimHowTogglePrompt<CR> 

