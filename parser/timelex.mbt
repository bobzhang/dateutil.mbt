// dateutil `_timelex`: breaks a time string into lexical units.

///|
priv enum LexState {
  Start
  Alpha // 'a'
  Num // '0'
  AlphaDot // 'a.'
  NumDot // '0.'
} derive(Eq)

///|
priv struct TimeLex {
  chars : Array[Char]
  mut pos : Int
  charstack : Array[Char]
  tokenstack : Array[String]
  mut eof : Bool
}

///|
fn TimeLex::new(s : String) -> TimeLex {
  { chars: s.to_array(), pos: 0, charstack: [], tokenstack: [], eof: false, }
}

///|
/// `instream.read(1)`; `None` at end of input.
fn TimeLex::read1(self : TimeLex) -> Char? {
  if self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    self.pos += 1
    Some(c)
  } else {
    None
  }
}

///|
/// `_split_decimal.split(token)` = `re.split("([.,])", token)`.
fn split_decimal(token : String) -> Array[String] {
  let out = []
  let cur = StringBuilder()
  for c in token {
    if c == '.' || c == ',' {
      out.push(cur.to_string())
      cur.reset()
      out.push(c.to_string())
    } else {
      cur.write_char(c)
    }
  }
  out.push(cur.to_string())
  out
}

///|
fn TimeLex::get_token(self : TimeLex) -> String? {
  if self.tokenstack.length() > 0 {
    return Some(self.tokenstack.remove(0))
  }
  let mut seenletters = false
  let token = StringBuilder()
  let mut has_token = false
  let mut state = Start
  let mut last = '\u{0}'
  while !self.eof {
    let nextchar = if self.charstack.length() > 0 {
      Some(self.charstack.remove(0))
    } else {
      let mut c = self.read1()
      while c is Some('\u{0}') {
        c = self.read1()
      }
      c
    }
    guard nextchar is Some(nextchar) else {
      self.eof = true
      break
    }
    let last_is_dot = last == '.'
    match state {
      Start => {
        has_token = true
        if py_isalpha_char(nextchar) {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          state = Alpha
        } else if py_isdigit_char(nextchar) {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          state = Num
        } else if py_isspace_char(nextchar) {
          token.write_char(' ')
          break
        } else {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          break
        }
      }
      Alpha => {
        seenletters = true
        if py_isalpha_char(nextchar) {
          token.write_char(nextchar)
          last = nextchar
        } else if nextchar == '.' {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          state = AlphaDot
        } else {
          self.charstack.push(nextchar)
          break
        }
      }
      Num =>
        if py_isdigit_char(nextchar) {
          token.write_char(nextchar)
          last = nextchar
        } else if nextchar == '.' ||
          (nextchar == ',' && py_len(token.to_string()) >= 2) {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          state = NumDot
        } else {
          self.charstack.push(nextchar)
          break
        }
      AlphaDot => {
        seenletters = true
        if nextchar == '.' || py_isalpha_char(nextchar) {
          token.write_char(nextchar)
          last = nextchar
        } else if py_isdigit_char(nextchar) && last_is_dot {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          state = NumDot
        } else {
          self.charstack.push(nextchar)
          break
        }
      }
      NumDot =>
        if nextchar == '.' || py_isdigit_char(nextchar) {
          token.write_char(nextchar)
          last = nextchar
        } else if py_isalpha_char(nextchar) && last_is_dot {
          {
            token.write_char(nextchar)
            last = nextchar
          }
          state = AlphaDot
        } else {
          self.charstack.push(nextchar)
          break
        }
    }
  }
  if !has_token {
    return None
  }
  let mut token = token.to_string()
  if (state == AlphaDot || state == NumDot) &&
    (seenletters || py_count(token, '.') > 1 || py_last(token) is ('.' | ',')) {
    let l = split_decimal(token)
    token = l[0]
    for tok in l[1:] {
      if tok != "" {
        self.tokenstack.push(tok)
      }
    }
  }
  if state == NumDot && py_count(token, '.') == 0 {
    token = token.replace_all(old=",", new=".")
  }
  Some(token)
}

///|
/// `_timelex.split(s)`: the token list dateutil's parser works on.
///
/// Tokens are runs of letters, runs of digits (possibly with a decimal
/// point), a single `" "` for any whitespace character, or single other
/// characters. NUL characters are skipped.
///
/// ```mbt check
/// test {
///   debug_inspect(
///     @parser.timelex_split("Sep.20.2009 4:30:21.447"),
///     content=(
///       #|["Sep", ".", "20", ".", "2009", " ", "4", ":", "30", ":", "21.447"]
///     ),
///   )
/// }
/// ```
pub fn timelex_split(s : String) -> Array[String] {
  let lex = TimeLex::new(s)
  let out = []
  while lex.get_token() is Some(tok) {
    out.push(tok)
  }
  out
}
