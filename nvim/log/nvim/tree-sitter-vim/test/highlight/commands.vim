" Last Change: 2022 Aug 19

command
" <- keyword

com
" <- keyword

command UserCommand
" <- keyword
"         ^ function.macro

command -complete=buffer UserCommand echo "toto"
" <- keyword
"           ^ property
"                   ^ constant
"                           ^ function.macro
"                                     ^ keyword
"                                             ^ string

command -complete=arglist UserCommand echo
" <- keyword
"           ^ property
"                   ^ constant
"                           ^ function.macro
"                                     ^ keyword

command -addr=lines -addr=arguments -addr=buffers -addr=loaded_buffers UserCommand echo
" <- keyword
"           ^ property
"               ^ constant
"                      ^ property
"                          ^ constant
"                                     ^ property
"                                         ^ constant
"                                                     ^ property
"                                                         ^ constant
"                                                                          ^ function.macro
"                                                                                    ^ keyword
"
command -addr=windows -addr=tabs -addr=quickfix -addr=other  UserCommand echo
" <- keyword
"           ^ property
"               ^ constant
"                      ^ property
"                             ^ constant
"                                   ^ property
"                                       ^ constant
"                                                 ^ property
"                                                     ^ constant
"                                                                ^ function.macro
"                                                                          ^ keyword
"

command -range=% UserCommand echo
" <- keyword
"           ^ property
"              ^ string.regex
"                   ^ function.macro
"                             ^ keyword

command -range=12 UserCommand echo
" <- keyword
"           ^ property
"              ^ number
"                   ^ function.macro
"                             ^ keyword

command -range UserCommand echo
" <- keyword
"           ^ property
"                 ^ function.macro
"                           ^ keyword

command -count UserCommand echo
" <- keyword
"           ^ property
"                 ^ function.macro
"                           ^ keyword
command -count UserCommand echo
" <- keyword
"           ^ property
"                 ^ function.macro
"                           ^ keyword

command -nargs=* -nargs=1 -nargs=? -nargs=+ UserCommand echo
" <- keyword
"           ^ property
"              ^ string.regex
"                    ^ property
"                       ^ number
"                            ^ property
"                                ^ string.regex
"                                     ^ property
"                                         ^ string.regex
"                                               ^ function.macro
"                                                         ^ keyword

command -buffer -bar -bang -keepscript -register UserCommand echo
" <- keyword
"           ^ property
"                 ^ property
"                             ^ property
"                                         ^ property
"                                                  ^ function.macro
"                                                            ^ keyword

" command UserCommand call Test()

" command -complete=syntax ToggleSyntax if exists("g:syntax_on") | syntax off | else | syntax enable | endif

" command -nargs=1 -complete=mapping Show echo "this is an error message"

" com -complete=custom,funcName -buffer -addr=tabs -bang ShowFunc execute "echo 'this is another error message'"
