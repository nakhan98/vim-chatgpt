" ChatGPT Vim Plugin
"
" Ensure Python3 is available
if !has('python3')
  echo "Python 3 support is required for ChatGPT plugin"
  finish
endif

" Set default values for Vim variables if they don't exist
if !exists("g:chat_gpt_max_tokens")
  let g:chat_gpt_max_tokens = 2000
endif

if !exists("g:chat_gpt_temperature")
  let g:chat_gpt_temperature = 0.7
endif

if !exists("g:chat_gpt_model")
  let g:chat_gpt_model = 'gpt-4o'
endif

if !exists("g:chat_gpt_lang")
  let g:chat_gpt_lang = ''
endif

if !exists("g:chat_gpt_split_direction")
  let g:chat_gpt_split_direction = 'horizontal'
endif

if !exists("g:split_ratio")
  let g:split_ratio = 3
endif

if !exists("g:chat_persona")
  let g:chat_persona = 'default'
endif

let code_wrapper_snippet = "Given the following code snippet: "
let g:prompt_templates = {
\ 'ask': '',
\ 'chat': '',
\ 'rewrite': 'Can you rewrite this more idiomatically? ' . code_wrapper_snippet,
\ 'review': 'Can you provide a code review? ' . code_wrapper_snippet,
\ 'document': 'Return documentation following language pattern conventions. ' . code_wrapper_snippet,
\ 'explain': 'Can you explain how this works? ' . code_wrapper_snippet,
\ 'test': 'Can you write a test? ' . code_wrapper_snippet,
\ 'fix':  'I have an error I need you to fix. ' . code_wrapper_snippet,
\}

if exists('g:chat_gpt_custom_prompts')
  call extend(g:prompt_templates, g:chat_gpt_custom_prompts)
endif

let g:promptKeys = keys(g:prompt_templates)

let g:gpt_personas = {
\ "default": 'You are a helpful expert programmer. We are working together to solve complex coding challenges and I need your help. Please make sure to wrap all code blocks in ``` and annotate the programming language you are using.',
\}

if exists('g:chat_gpt_custom_persona')
  call extend(g:gpt_personas, g:chat_gpt_custom_persona)
endif
"
" Function to show ChatGPT responses in a new buffer
function! DisplayChatGPTResponse(response, finish_reason, chat_gpt_session_id)
  let response = a:response
  let finish_reason = a:finish_reason

  let chat_gpt_session_id = a:chat_gpt_session_id

  if !bufexists(chat_gpt_session_id)
    if g:chat_gpt_split_direction ==# 'vertical'
      silent execute winwidth(0)/g:split_ratio.'vnew '. chat_gpt_session_id
    else
      silent execute winheight(0)/g:split_ratio.'new '. chat_gpt_session_id
    endif
    call setbufvar(chat_gpt_session_id, '&buftype', 'nofile')
    call setbufvar(chat_gpt_session_id, '&bufhidden', 'hide')
    call setbufvar(chat_gpt_session_id, '&swapfile', 0)
    setlocal modifiable
    setlocal wrap
    call setbufvar(chat_gpt_session_id, '&ft', 'markdown')
    call setbufvar(chat_gpt_session_id, '&syntax', 'markdown')
  endif

  if bufwinnr(chat_gpt_session_id) == -1
    if g:chat_gpt_split_direction ==# 'vertical'
      execute winwidth(0)/g:split_ratio.'vsplit ' . chat_gpt_session_id
    else
      execute winheight(0)/g:split_ratio.'split ' . chat_gpt_session_id
    endif
  endif

  let last_lines = getbufline(chat_gpt_session_id, '$')
  let last_line = empty(last_lines) ? '' : last_lines[-1]

  let new_lines = substitute(last_line . response, '\n', '\r\n\r', 'g')
  let lines = split(new_lines, '\n')

  let clean_lines = []
  for line in lines
    call add(clean_lines, substitute(line, '\r', '', 'g'))
  endfor

  call setbufline(chat_gpt_session_id, '$', clean_lines)

  execute bufwinnr(chat_gpt_session_id) . 'wincmd w'
  " Move the viewport to the bottom of the buffer
  normal! G
  call cursor('$', 1)

  " if finish_reason != ''
  "   wincmd p
  " endif
endfunction

" Function to interact with ChatGPT
function! ChatGPT(prompt) abort
  python3 << EOF

import sys
import vim
import os

try:
    from openai import AzureOpenAI, OpenAI
except ImportError:
    print("Error: openai module not found. Please install with Pip and ensure equality of the versions given by :!python3 -V, and :python3 import sys; print(sys.version)")
    raise

def safe_vim_eval(expression):
    try:
        return vim.eval(expression)
    except vim.error:
        return None

def create_client():
    api_type = safe_vim_eval('g:api_type')
    api_key = os.getenv('OPENAI_API_KEY') or safe_vim_eval('g:chat_gpt_key') or safe_vim_eval('g:openai_api_key')
    openai_base_url = (os.getenv('OPENAI_PROXY') or os.getenv('OPENAI_API_BASE')
        or safe_vim_eval('g:openai_base_url'))

    if api_type == 'azure':
        azure_endpoint = safe_vim_eval('g:azure_endpoint')
        azure_api_version = safe_vim_eval('g:azure_api_version')
        azure_deployment = safe_vim_eval('g:azure_deployment')
        assert azure_endpoint and azure_api_version and azure_deployment, "azure_endpoint, azure_api_version and azure_deployment not set property, please check your settings in `vimrc` or `enviroment`."
        assert api_key, "api_key not set, please configure your `openai_api_key` in your `vimrc` or `enviroment`"
        client = AzureOpenAI(
            azure_endpoint=azure_endpoint,
            azure_deployment=azure_deployment,
            api_key=api_key,
            api_version=azure_api_version,
        )
    else:
        client = OpenAI(
            base_url=openai_base_url,
            api_key=api_key,
        )
    return client


def chat_gpt(prompt):
  token_limits = {
    "gpt-3.5-turbo": 4097,
    "gpt-3.5-turbo-16k": 16385,
    "gpt-3.5-turbo-1106": 16385,
    "gpt-4": 8192,
    "gpt-4-turbo": 128000,
    "gpt-4-turbo-preview": 128000,
    "gpt-4-32k": 32768,
    "gpt-4o": 128000,
  }

  max_tokens = int(vim.eval('g:chat_gpt_max_tokens'))
  model = str(vim.eval('g:chat_gpt_model'))
  temperature = float(vim.eval('g:chat_gpt_temperature'))
  lang = str(vim.eval('g:chat_gpt_lang'))
  resp = lang and f" And respond in {lang}." or ""

  personas = dict(vim.eval('g:gpt_personas'))
  persona  = str(vim.eval('g:chat_persona'))

  systemCtx = {"role": "system", "content": f"{personas[persona]} {resp}"}
  messages = []
  session_id = 'gpt-persistent-session' if int(vim.eval('exists("g:chat_gpt_session_mode") ? g:chat_gpt_session_mode : 1')) == 1 else None

  # If session id exists and is in vim buffers
  if session_id:
    buffer = []

    for b in vim.buffers:
       # If the buffer name matches the session id
      if session_id in b.name:
        buffer = b[:]
        break

    # Read the lines from the buffer
    history = "\n".join(buffer).split('\n\n>>>')
    history.reverse()

    # Adding messages to history until token limit is reached
    token_count = token_limits.get(model, 4097) - max_tokens - len(prompt) - len(str(systemCtx))

    for line in history:
      if ':\n' in line:
        role, message = line.split(":\n")

        token_count -= len(message)

        if token_count > 0:
            messages.insert(0, {
                "role": role.lower(),
                "content": message
            })

  if session_id:
    content = '\n\n>>>User:\n' + prompt + '\n\n>>>Assistant:\n'.replace("'", "''")

    vim.command("call DisplayChatGPTResponse('{0}', '', '{1}')".format(content.replace("'", "''"), session_id))
    vim.command("redraw")

  messages.append({"role": "user", "content": prompt})
  messages.insert(0, systemCtx)

  try:
    client = create_client()
    response = client.chat.completions.create(
        model=model,
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
        stop='',
        stream=True
    )

    # Iterate through the response chunks
    for chunk in response:
      # newer Azure API responses contain empty chunks in the first streamed
      # response
      if not chunk.choices:
          continue

      chunk_session_id = session_id if session_id else chunk.id
      choice = chunk.choices[0]
      finish_reason = choice.finish_reason
      content = choice.delta.content

      # Call DisplayChatGPTResponse with the finish_reason or content
      if finish_reason:
        vim.command("call DisplayChatGPTResponse('', '{0}', '{1}')".format(finish_reason.replace("'", "''"), chunk_session_id))
      elif content:
        vim.command("call DisplayChatGPTResponse('{0}', '', '{1}')".format(content.replace("'", "''"), chunk_session_id))

      vim.command("redraw")

  except Exception as e:
    print("Error:", str(e))

chat_gpt(vim.eval('a:prompt'))
EOF
endfunction

" Function to send highlighted code to ChatGPT
function! SendHighlightedCodeToChatGPT(ask, context)

  " Ignore text selection if chat selected
  if a:ask ==# 'chat'
    execute "normal! v\<Esc>"
  endif

  let save_cursor = getcurpos()

  " Save the current yank register
  let save_reg = @@
  let save_regtype = getregtype('@')

  let [line_start, col_start] = getpos("'<")[1:2]
  let [line_end, col_end] = getpos("'>")[1:2]

  " Yank the visually selected text into the unnamed register
  execute 'normal! ' . line_start . 'G' . col_start . '|v' . line_end . 'G' . col_end . '|y'

  " Send the yanked text to ChatGPT
  let yanked_text = ''
  let syntax = &syntax

  if (col_end - col_start > 0) || (line_end - line_start > 0)
    let yanked_text = '```' . syntax . "\n" . @@ . "\n" . '```'
  endif

  let prompt = a:context . ' ' . "\n" . yanked_text

  echo a:ask
  if has_key(g:prompt_templates, a:ask)
    let template  = g:prompt_templates[a:ask]

    if len(yanked_text) > 0
      let template = template
    endif

    let prompt = template . "\n" . yanked_text . "\n" . a:context
  endif

  call ChatGPT(prompt)

  " Restore the original yank register
  let @@ = save_reg
  call setreg('@', save_reg, save_regtype)
  let curpos = getcurpos()
  call setpos("'<", curpos)
  call setpos("'>", curpos)
  call setpos('.', save_cursor)

endfunction
"
" Function to generate a commit message
function! GenerateCommitMessage()
  " Save the current position and yank register
  let save_cursor = getcurpos()
  let save_reg = @@
  let save_regtype = getregtype('@')

  " Yank the entire buffer into the unnamed register
  normal! ggVGy

  " Send the yanked text to ChatGPT
  let yanked_text = @@
  let prompt = 'I have the following code changes, can you write a helpful commit message, including a short title? Only respond with the commit message' . "\n" .  yanked_text
  let g:chat_gpt_session_mode = 0

  call ChatGPT(prompt)
endfunction

" Menu for ChatGPT
if has('nvim')
  " Menu for ChatGPT using inputlist for Neovim
  function! s:ChatGPTMenuSink(choice)
    let choices = {}

    for index in range(len(g:promptKeys))
      let choices[index+1] = g:promptKeys[index]
    endfor

    if a:choice > 0 && a:choice <= len(g:promptKeys)
      call SendHighlightedCodeToChatGPT(choices[a:choice], input('Prompt > '))
    endif
  endfunction

  function! ChatGPTMenu() range
    let menu_choices = ['ChatGPT-Vim Mod', '---------------']

    for index in range(len(g:promptKeys))
      call add(menu_choices, string(index + 1) . ". " . Capitalize(g:promptKeys[index]))
    endfor

    let choice = inputlist(menu_choices)
    call s:ChatGPTMenuSink(choice)
  endfunction
else
  " Original menu for Vim
  function! s:ChatGPTMenuSink(id, choice)
    call popup_hide(a:id)
    let choices = {}

    for index in range(len(g:promptKeys))
      let choices[index+1] = g:promptKeys[index]
    endfor

    if a:choice > 0 && a:choice <= len(g:promptKeys)
      call SendHighlightedCodeToChatGPT(choices[a:choice], input('Prompt > '))
    endif
  endfunction

  function! s:ChatGPTMenuFilter(id, key)

    if a:key > 0 && a:key <= len(g:promptKeys)
      call s:ChatGPTMenuSink(a:id, a:key)
    else " No shortcut, pass to generic filter
      return popup_filter_menu(a:id, a:key)
    endif
  endfunction

  function! ChatGPTMenu() range
    echo a:firstline. a:lastline
    let menu_choices = []

    for index in range(len(g:promptKeys))
      call add(menu_choices, string(index + 1) . ". " . g:promptKeys[index])
    endfor

    call popup_menu(menu_choices, #{
          \ pos: 'topleft',
          \ line: 'cursor',
          \ col: 'cursor+2',
          \ title: ' Chat GPT ',
          \ highlight: 'question',
          \ borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
          \ callback: function('s:ChatGPTMenuSink'),
          \ border: [],
          \ cursorline: 1,
          \ padding: [0,1,0,1],
          \ filter: function('s:ChatGPTMenuFilter'),
          \ mapping: 0,
          \ })
  endfunction
endif

" Expose mappings
vnoremap <silent> <Plug>(chatgpt-menu) :call ChatGPTMenu()<CR>

function! Capitalize(str)
    return toupper(strpart(a:str, 0, 1)) . tolower(strpart(a:str, 1))
endfunction

for i in range(len(g:promptKeys))
  " Commands to interact with ChatGPT
  execute 'command! -range -nargs=? ' . Capitalize(g:promptKeys[i]) . " call SendHighlightedCodeToChatGPT('" . g:promptKeys[i] . "',<q-args>)"
endfor

command! GenerateCommit call GenerateCommitMessage()

function! SetPersona(persona)
    let personas = keys(g:gpt_personas)
    if index(personas, a:persona) != -1
      echo 'Persona set to: ' . a:persona
      let g:chat_persona = a:persona
    else
      let g:chat_persona = 'default'
      echo 'Persona set to default, not found ' . a:persona
    end
endfunction

function! s:ClearChatGPTSession()
  " Check if the buffer exists
  if bufexists('gpt-persistent-session')
    " Get the buffer number
    let bufnr = bufnr('gpt-persistent-session')

    " Delete all lines in the buffer
    silent! call deletebufline(bufnr, 1, '$')

    " Find and close all windows displaying this buffer, except the active one
    let active_winid = win_getid()
    for winid in win_findbuf(bufnr)
      if winid != active_winid
        call win_execute(winid, 'close')
      endif
    endfor

    " Enter and exit visual mode to clear previous visual selection
    execute "normal! v\<Esc>"
    echo "ChatGPT session content cleared"
  else
    echo "No active ChatGPT session found"
  endif
endfunction

command! ClearChatGPTSession call s:ClearChatGPTSession()

function! s:SetChatGPTAPIKey()
    let g:chat_gpt_key = trim(input("Enter ChatGPT API key: "))
endfunction

command! SetChatGPTAPIKey call s:SetChatGPTAPIKey()

function! s:SetOpenAIBaseURL()
    let g:openai_base_url = trim(input("Enter OpenAI base URL: "))
endfunction

command! SetOpenAIBaseURL call s:SetOpenAIBaseURL()

command! -nargs=1 GptBe call SetPersona(<q-args>)

" For debugging
" function! PrintVisualSelectionPositions()
"   echo "Start position: " . string(getpos("'<"))
"   echo "End position: " . string(getpos("'>"))
"   echo "Current position: " . string(getcurpos())
" endfunction

" function! SetVisualMarksToCursor()
"   let curpos = getcurpos()
"   " execute "normal! v\<Esc>"
"   call setpos("'<", curpos)
"   call setpos("'>", curpos)
"   echo "Visual marks set to cursor position: " . string(curpos)
" endfunction
