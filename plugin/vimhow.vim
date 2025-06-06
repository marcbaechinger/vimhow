if exists("g:loaded_vimhow")
   finish
endif
let g:loaded_vimhow = 1

python3 << EOF
# Imports Python modules to be used by the plugin.
import sys
import threading

def VimHowSafeImport(module_names):
  for module_name in module_names:
    try:
        __import__(module_name)
    except ImportError:
        print(f"Warning: can't import {module_name}")
        return False
  return True

def VimHowAppendToSysPath(paths: list[str]):
  for path in paths:
    evaled_path = vim.eval(f"expand('{path}')")
    sys.path.append(evaled_path)

VimHowAppendToSysPath(
  [
    '~/.vim/bundle/vimhow/autoload/', 
    '~/.vim/bundle/vimhow/.venv/lib/python3.13/site-packages',  
  ]
)
vimHowHasTutor = False
api_key = None
vimHowRequiredImports = ["google.genai", "vimhowtutor"]
if VimHowSafeImport(vimHowRequiredImports):
  from vimhowtutor import VimTutor
  from api_key import get_api_key
  api_key = get_api_key()
  vimHowHasTutor = api_key is not None

vimHowSystemInstruction = """You are an expert vim tutor. You give clear and concise advice on how to use vim. Your output are vim commands or vimscript functions that help the user programming with vim. Start with the sequence of commands or the functions and then explain step by step how the user can achieve the declared goal. 

Purpose and Goals:
  * Provide accurate and efficient Vim commands and Vimscript functions to assist users in their programming tasks.
  * Offer clear, step-by-step explanations for each command or function, ensuring user understanding.
  * Maintain conciseness and adhere to the specified output format (markdown, 80-character line width).


Behaviors and Rules:

1) Command/Function Provision:
  a) Based on the user's request, provide the most relevant Vim commands or Vimscript functions.
  b) Always present the commands/functions first, as a complete sequence or a standalone function.
  c) Ensure commands are executable and functions are syntactically correct.

2) Step-by-Step Explanation:
  a) After presenting the commands/functions, provide a detailed, step-by-step explanation of how to use them.
  b) Break down complex tasks into manageable sub-steps.
  c) Use clear, unambiguous language, avoiding jargon where simpler terms suffice.
  d) Illustrate with examples where helpful.
  e) Recommend plugins in case there are plugins that are helpfule for the task

3) Formatting and Style:
  a) All output must be in markdown format.
  b) Strictly adhere to a line width of 80 characters, wrapping lines as necessary.
  c) Be concise; avoid verbose explanations or unnecessary conversational fillers.


Overall Tone:
  * Authoritative and knowledgeable.
  * Direct and to the point.
  * Patient and helpful, but focused on efficient instruction."""

if api_key is None:
  print("please provide an API key as env variable GOOGLE_API_KEY to use the Gemini API")
elif not vimHowHasTutor:
  print("some required imports not available out of ", vimHowRequiredImports)
else:
  vimTutor = VimTutor(api_key, vimHowSystemInstruction, vim.eval("expand('~/.vimhow/trace')")
)

def VimHowSetNavigationInfo(index):
  size = len(vimTutor.history.entries)
  navigationInfo = f"({index + 1}/{size})"
  vim.command(f"let g:VimHowNavigationInfo = '{navigationInfo}'")
  return navigationInfo

def VimHowPromptCallback():
  index, historyItem = vimTutor.get_last()
  VimHowSetNavigationInfo(index)
  vim.command("call VimHowFetchResponse()");

def VimHowPromptBlocking(prompt):
  vimTutor.prompt(prompt.decode('utf-8'))
  VimHowPromptCallback()

def VimHowPromptAsync():
  prompt = vim.vars['VimHowValue']
  thread = threading.Thread(
      target=VimHowPromptBlocking,
      args = (prompt,)
  )
  thread.daemon = True 
  thread.start()
  return ""

def VimHowSelectAndReturnPreviousResponse():
  prev = vimTutor.select_previous()
  if prev is None:
    return ""
  size = len(vimTutor.history.entries)
  navigationInfo = VimHowSetNavigationInfo(prev[0])
  header = f"# -- {navigationInfo} in history --\n"
  historyItem = prev[1]
  return header + historyItem.response

def VimHowSelectAndReturnNextResponse():
  nextItem = vimTutor.select_next()
  if nextItem is None:
    return "" 
  size = len(vimTutor.history.entries)
  index = nextItem[0]
  navigationInfo = VimHowSetNavigationInfo(index)
  header = f"# -- {navigationInfo} in history --\n" if index < size else ""
  historyItem = nextItem[1]
  return header + historyItem.response

def VimHowGetTotalTokenStats():
  if not vimHowHasTutor:
    return "0/0"
  return str(vimTutor.get_prompt_token_count()) + "/" + str(vimTutor.get_candidates_token_count())

def VimHowGetSelectedTokenStats():
  if not vimHowHasTutor:
    return "-/-"
  _ , historyEvent = vimTutor.get_selected()
  if historyEvent is not None:
    return str(historyEvent.prompt_token_count) + "/" + str(historyEvent.candidates_token_count)
  else:
    return "-/-"

EOF

let s:promptBufferName = expand('~') . '/.vimhow/prompt.vimhow'
let s:responseBufferName = expand('~') . '/.vimhow/response.md'
let s:window_counter = 1
let s:readOnlyMarker = "^>"
let s:statusDefault = "Enter prompt."
let s:statusEditing = "Leave normal mode."
let s:statusEdited = "Press ? to prompt."
let s:statusThinking = "Sent prompt. Thinking..."
let s:statusResponded = "Response written."
let s:isAiThinking = 0

let g:VimHowStatus = "Not yet started"
let g:VimHowTotalTokenStats = "[-/-]"
let g:VimHowSelectedTokenStats = "[-/-]"
let g:VimHowNavigationInfo = ""

function! s:setVimHowStatus(status)
  let g:VimHowStatus = a:status
endfunction

function! s:getTotalTokenStats()
  let g:VimHowTotalTokenStats = py3eval('VimHowGetTotalTokenStats()')
endfunction

function! s:getSelectedTokenStats()
  let g:VimHowSelectedTokenStats = py3eval('VimHowGetSelectedTokenStats()')
endfunction

call s:getTotalTokenStats()
call s:getSelectedTokenStats()

function! s:appendToPrompt(text, markAsReadOnly)
  let winid = s:getPromptWinId()
  if winid != -1
    let lastLine = line('$', winid)
    let bufname = bufname(s:promptBufferNr)
    call appendbufline(bufname, lastLine, a:text) 
    let insertion_end = line('$', winid)
    if a:markAsReadOnly
      call s:markLinesReadOnly(lastLine, lastLine + 1, bufname)
    endif
  endif
endfunction

function! s:askTutor(prompt)
  let g:VimHowValue = trim(a:prompt)
  let nothing = py3eval('VimHowPromptAsync()')
  call s:setVimHowStatus(s:statusThinking)
  let s:isAiThinking = 1
endfunction

function! VimHowFetchResponse()
  let s:isAiThinking = 0
  let code = py3eval('vimTutor.get_last_response()')
  call s:renderResponse(code) 
  call s:getSelectedTokenStats()
  call s:setVimHowStatus(s:statusResponded . " ->")
  call s:getTotalTokenStats()
  redraw!
endfunction

function! s:renderResponse(code)
  let winid = s:getResponseWinId()
  if winid != -1
    let lastLine = line('$', winid)
    let bufname = bufname(s:responseBufferNr)
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

function! s:getMarkdownCodeBlock()
  let current_line = line('.')
  let in_code_block = 0
  let start_line = 0
  let end_line = 0

  " Check if current line is within a fenced code block
  for line_num in range(current_line, 1, -1)
    let line_text = getline(line_num)
    if line_text =~ '^```\zs\l\+'
      let in_code_block = 1
      let start_line = line_num
      break
    elseif line_text =~ '^```$'
      break
    endif
  endfor

  if !in_code_block
    return ''
  endif

  for line_num in range(current_line, line('$'))
    let line_text = getline(line_num)
    if line_text =~ '^```$'
      let end_line = line_num
      break
    endif
  endfor

  if end_line == 0
    return ''
  endif

  " Extract the code block
  let code_block_lines = getline(start_line + 1, end_line - 1)
  let code_block = join(code_block_lines, "\n")

  let @a = code_block
endfunction

function! s:togglePrompt()
  call s:ensureDirectoryExists(expand('~') . '/.vimhow')
  if !exists("s:promptBufferNr")
    let s:windowId = s:window_counter
    let s:promptBufferNr = 0
    let s:responseBufferNr = 0
    let s:window_counter = s:window_counter + 1
    call s:setVimHowStatus(s:statusDefault)
  endif
  if s:promptBufferNr && bufexists(s:promptBufferName)
    execute 'bd!' s:promptBufferNr
    execute 'bd!' s:responseBufferNr
    let s:promptBufferNr = 0
    let s:responseBufferNr = 0
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
    let s:promptBufferNr = bufnr(s:promptBufferName)
    let s:responseBufferNr = bufnr(s:responseBufferName)
    let &splitright = old_splitright
    silent! execute '$'
    normal! ^
  endif
endfunction

function! s:how(query)
    if trim(a:query) ==# ""
      call s:echoWarning("Empty prompt")
      call s:setVimHowStatus(s:statusDefault)
      return
    endif
    let g:VimHowStatus = "Asking tutor..."
    call s:askTutor(a:query)
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
      call s:setVimHowStatus(s:statusDefault)
      return
    endif
    let prompt = join(filteredLines, "\n")
    call s:markLinesReadOnly(0, lastLineNr, s:promptBufferName)
    let g:VimHowStatus = "Asking tutor..."
    write
    call s:askTutor(prompt)
  endif
endfunction

function! s:displayPrevious()
  let response = py3eval('VimHowSelectAndReturnPreviousResponse()')
  if response ==# ''
    echo "Already at the end of the history"
  else
    call s:renderResponse(response)
    call s:getSelectedTokenStats()
  endif
endfunction

function! s:displayNext()
  let response = py3eval('VimHowSelectAndReturnNextResponse()')
  if response ==# ''
    echo "Already at the actual output"
  else
    call s:renderResponse(response)
    call s:getSelectedTokenStats()
  endif
endfunction

function! s:popupPrompt()
  let lNum = line('.')
  let prompt = trim(py3eval('vimTutor.get_selected_prompt()'))
  call setreg("*", prompt)
  let options = #{line: 0, col: 0, title:' Last prompt', time:10000, maxwidth:72, close:'click'}
  call popup_notification(split(prompt, "\n", 1), options)
endfunction

function s:hasPrompt()
  if s:promptBufferNr
    for line in getbufline(s:promptBufferName, 1, '$')
      if line !~# '^>'
        return 1
      endif
    endfor
  endif
  return 0
endfunction

function! s:setVimHowStatusAfterEditing()
  if s:isAiThinking
    return
  endif
  if s:hasPrompt() == 1
    call s:setVimHowStatus(s:statusEdited)
  else
    call s:setVimHowStatus(s:statusDefault)
  endif
endfunction

" UI functions

function! s:getPromptWinId()
  if !s:promptBufferNr
    return -1
  endif
  let winids = win_findbuf(s:promptBufferNr)
  if !empty(winids)
    return winids[0]
  endif
  return -1
endfunction

function! s:getResponseWinId()
  if !s:responseBufferNr
    return -1
  endif
  let winids = win_findbuf(s:responseBufferNr)
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

function! s:echoWarning(message)
  call s:echoColoredMessage("WarningMsg", a:message)
endfunction
 
function! s:echoError(message)
  call s:echoColoredMessage("ErrorMsg", a:message)
endfunction
 
function! s:echoColoredMessage(color, message)
  " Use hl groups WarningMsg, ErrorMsg, InfoMsg. See `:h echohl` for details
  execute 'echohl ' . a:color
  echomsg a:message
  echohl None
endfunction

" define auto commands

if !exists(":VimHowTogglePrompt")
  command -nargs=0  VimHowTogglePrompt :call s:togglePrompt()
  command -nargs=0  VimHowPrompt :call s:prompt(s:promptBufferName)
  command -nargs=1  VimHow :call s:how(<args>)
  command -nargs=0  VimHowSelectPrevious :call s:displayPrevious()
  command -nargs=0  VimHowSelectNext :call s:displayNext()
  command -nargs=0  VimHowPopupPrompt :call s:popupPrompt()
  command -nargs=0  VimHowCopyCodeBlock :call s:getMarkdownCodeBlock()
endif

augroup VimHowAutoCommands
  au! BufRead,BufNewFile *.vimhow set filetype=vimhow
  au! BufEnter,BufLeave *.vimhow :call s:setVimHowStatus(s:statusDefault)
  au! InsertEnter *.vimhow :call s:setVimHowStatus(s:statusEditing)
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

