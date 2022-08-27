const json = require("tree-sitter-json/grammar");

module.exports = grammar(json, {
  name: "jsonc",

  extras: ($, original) => [...original, $.comment],

  rules: {
    document: ($, original) => optional(original),

    comment: ($) =>
      token(
        choice(seq("//", /.*/), seq("/*", /[^*]*\*+([^/*][^*]*\*+)*/, "/"))
      ),
  },
});
