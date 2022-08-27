module.exports = grammar({
  name: 'pioasm',

  externals: $ => [$.code_block_body],

  rules: {
    source_file: $ => $._lines,

    _lines: $ => prec.left(choice($._line, seq($._lines, '\n', optional($._line)))),

    _line: $ => choice(
      $.line_comment,
      seq(
        choice(
          $.directive,
          $.instruction,
          seq($.label_decl, $.instruction),
          $.label_decl,
          $.code_block
        ),
        optional($.line_comment)
      )
    ),

    directive: $ => choice(
      seq(field('directive', '.program'), $.identifier),
      seq(field('directive', '.define'), $.symbol_def, $.expression),
      seq(field('directive', '.origin'), $.value),
      seq(field('directive', '.side_set'), $.value, optional($.optional), optional('pindirs')),
      field('directive', '.wrap_target'),
      field('directive', '.wrap'),
      seq(field('directive', '.word'), $.value),
      seq(field('directive', '.lang_opt'), $.non_ws, $.non_ws, '=', choice($.integer, $.string, $.non_ws)),
    ),

    instruction: $ => choice(
      seq($._base_instruction, $.sideset, $.delay),
      seq($._base_instruction, $.delay, $.sideset),
      seq($._base_instruction, $.sideset),
      seq($._base_instruction, $.delay),
      seq($._base_instruction),
    ),

    _base_instruction: $ => choice(
      field('opcode', 'nop'),
      seq(field('opcode', 'jmp'), optional($.condition), optional(','), $.expression),
      seq(field('opcode', 'wait'), optional($.value), $.wait_source),
      seq(field('opcode', 'wait'), $.value, ',', $.value),
      seq(field('opcode', 'in'), $.in_source, optional(','), $.value),
      seq(field('opcode', 'out'), $.out_target, optional(','), $.value),
      seq(field('opcode', 'push'), optional('iffull'), optional($._blocking)),
      seq(field('opcode', 'pull'), optional('ifempty'), optional($._blocking)),
      seq(field('opcode', 'mov'), $.mov_target, optional(','), optional($.mov_op), $.mov_source),
      seq(field('opcode', 'irq'), optional($.irq_modifiers), $.value, optional('rel')),
      seq(field('opcode', 'set'), $.set_target, optional(','), $.value)
    ),

    _blocking: $ => choice('block', 'noblock'),

    condition: $ => choice(
      seq($.not, 'x'),
      seq('x', '--'),
      seq($.not, 'y'),
      seq('y', '--'),
      seq('x', '!=', 'y'),
      'pin',
      seq($.not, 'osre'),
    ),

    wait_source: $ => choice(
      seq('irq', optional(','), $.value, optional('rel')),
      seq('gpio', optional(','), $.value),
      seq('pin', optional(','), $.value),
    ),

    in_source: $ => choice(
      'pins',
      'x',
      'y',
      'null',
      'isr',
      'osr',
      'status'
    ),

    out_target: $ => choice(
      'pins',
      'x',
      'y',
      'null',
      'pindirs',
      'isr',
      'pc',
      'exec'
    ),

    mov_target: $ => choice(
      'pins',
      'x',
      'y',
      'exec',
      'pc',
      'isr',
      'osr'
    ),

    mov_source: $ => choice(
      'pins',
      'x',
      'y',
      'null',
      'status',
      'isr',
      'osr'
    ),

    mov_op: $ => choice(
      $.not,
      '::'
    ),

    irq_modifiers: $ => choice(
      'clear',
      'wait',
      'nowait',
      'set',
    ),

    set_target: $ => choice(
      'pins',
      'x',
      'y',
      'pindirs'
    ),

    sideset: $ => seq(choice('side', 'sideset', 'side_set'), $.value),
    delay: $ => seq('[', $.expression, ']'),

    symbol_def: $ => choice(
      $.identifier,
      seq('public', $.identifier),
      seq('*', $.identifier)
    ),

    value: $ => choice(
      $.integer,
      $.identifier,
      seq('(', $.expression, ')')
    ),

    expression: $ => choice(
      $.value,
      prec.left(3, seq($.expression, '+', $.expression)),
      prec.left(3, seq($.expression, '-', $.expression)),
      prec.left(4, seq($.expression, '*', $.expression)),
      prec.left(4, seq($.expression, '/', $.expression)),
      prec.left(2, seq($.expression, '|', $.expression)),
      prec.left(2, seq($.expression, '&', $.expression)),
      prec.left(2, seq($.expression, '^', $.expression)),
      prec.left(5, seq('-', $.expression)),
      prec.left(5, seq('::', $.expression))
    ),

    label_decl: $ => seq($.symbol_def, ':'),
    code_block: $ => seq(
      '%',
      $.code_block_language,
      '{',
      $.code_block_body,
      '%}'
    ),
    code_block_language: $ => /[a-z-]+/,

    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
    integer: $ => /0x[0-9a-fA-F]+|0b[01]+|[0-9]+|ONE|ZERO/,
    non_ws: $ => /[^ \t\n"=]+/,
    string: $ => /"[^\n]*"/,

    not: $ => /[~!]/,

    optional: $ => choice('opt', 'optional'),

    block_comment: $ => seq(
      '/*',
      /[^*]*\*+([^/*][^*]*\*+)*/,
      '/'
    ),
    line_comment: $ => /(?:\/\/|;).*/
  },

  extras: $ => [/[ \t]+/, $.block_comment]
});
