local status, fzf = pcall(require, "fzf")
if (not status) then
  print("fzf is not installed")
  return
end

vim.cmd[[
nnoremap <silent> <Leader>. :<C-u>FZFFileList<CR>
nnoremap <silent> <Leader>, :<C-u>FZFMru<CR>
nnoremap <silent> <Leader>l :<C-u>Lines<CR>
nnoremap <silent> <Leader>b :<C-u>Buffers<CR>
nnoremap <silent> <Leader>k :<C-u>Rg<CR>
command! FZFFileList call fzf#run({
           \ 'source': 'rg --files --hidden',
           \ 'sink': 'e',
           \ 'options': '-m --border=none',
           \ 'down': '20%'})
command! FZFMru call fzf#run({
           \ 'source': v:oldfiles,
           \ 'sink': 'e',
           \ 'options': '-m +s --border=none',
           \ 'down':  '20%'})

let g:fzf_layout = {'up':'~90%', 'window': { 'width': 0.8, 'height': 0.8,'yoffset':0.5,'xoffset': 0.5, 'border': 'none' } }

augroup vimrc_fzf
autocmd!
autocmd FileType fzf tnoremap <silent> <buffer> <Esc> <C-g>
autocmd FileType fzf set laststatus=0 noshowmode noruler
     \| autocmd BufLeave <buffer> set laststatus=2 noshowmode ruler
augroup END

function! RipgrepFzf(query, fullscreen)
   let command_fmt = 'rg --column --hiddden --line-number --no-heading --color=always --smart-case %s || true'
   let initial_command = printf(command_fmt, shellescape(a:query))
   let reload_command = printf(command_fmt, '{q}')
   let spec = {'options': ['--phony', '--query', a:query, '--bind', 'change:reload:'.reload_command]}
   call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), a:fullscreen)
endfunction

command! -nargs=* -bang RG call RipgrepFzf(<q-args>, <bang>0)
]]
