# The parser builds an AST from a stream of tokens.
#
# A node in the AST is a JavaScript array whose first item is a string
# indicating the type of node.  The rest of the items represent the content of
# a node.  For instance, "(1 + 2) × 3 4" will produce the tree:
#
#     ['body',
#       ['expr',
#         ['expr',
#           ['number', '1'],
#           ['symbol', '+'],
#           ['number', '2']],
#         ['symbol', '×'],
#         ['number', '3'],
#         ['number', '4']]]
#
# Note, that right after parsing stage we don't yet know which symbols
# represent verbs and which represent nouns.  This will be resolved later in
# the compiler.
#
# This parser is a hand-crafted recursive descent parser.  Various parseX()
# functions roughly correspond to the set of non-terminals in an imaginary
# grammar.
parse = (aplCode, opts = {}) ->
  tokens = tokenize aplCode
  i = 0

  # A single-token lookahead is used.  Variable `token` stores the upcoming
  # token.
  token = tokens[i++]

  # `consume(tt)` consumes the upcoming token and returns a truthy value only
  # if its type matches `tt`.  A space-separated value of `tt` matches any of
  # a set of token types.
  macro consume (tt) ->
    new macro.Parens macro.csToNode """
      if token.type in #{JSON.stringify macro.nodeToVal(tt).split ' '}
        token = tokens[i++]
    """

  # `demand(tt)` is like `consume(tt)` but intolerant to a mismatch.
  macro demand (tt) ->
    new macro.Parens macro.codeToNode(->
      if token.type is tt then token = tokens[i++]
      else parserError "Expected token of type '#{tt}' but got '#{token.type}'"
    ).subst {tt}

  parserError = (message) ->
    throw SyntaxError message,
      file: opts.file, line: token.startLine, col: token.startCol, aplCode: aplCode

  parseBody = ->
    body = ['body']
    loop
      if token.type in ['eof', '}'] then return body
      while consume 'separator newline' then ;
      if token.type in ['eof', '}'] then return body
      expr = parseExpr()
      if consume ':' then expr = ['guard', expr, parseExpr()]
      body.push expr

  parseExpr = ->
    expr = ['expr']
    loop
      t = token
      if consume 'number string symbol embedded' then item = [t.type, t.value]
      else if consume '(' then item = parseExpr(); demand ')'
      else if consume '{' then b = parseBody(); demand '}'; item = ['lambda', b]
      else parserError "Encountered unexpected token of type '#{token.type}'"
      if consume '['
        item = ['index', item]
        loop
          if consume ';' then item.push null
          else if token.type is ']' then item.push null; break
          else (item.push parseExpr(); if token.type is ']' then break else demand ';')
        demand ']'
      if consume '←' then return expr.concat [['assign', item, parseExpr()]]
      expr.push item
      if token.type in ') ] } : ; separator newline eof'.split ' ' then return expr

  result = parseBody()
  # 'hello'} !!! SYNTAX ERROR
  demand 'eof'
  result

  macro ->
    delete macro._macros.consume
    delete macro._macros.demand
    return
