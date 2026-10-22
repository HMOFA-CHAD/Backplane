import Base
import ./check.bend as C
import ../src/web/dom.bend as D

def attrs(as: List<&2, D.Attr>) -> String:
  match as:
    case Nil{}:
      ""
    case D.At{n, v} <> t:
      " " ++ n ++ "=" ++ v ++ attrs(t)
    case D.On{e, a} <> t:
      " on" ++ e ++ "=" ++ a ++ attrs(t)

def shows(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case D.Txt{s} <> t:
      s ++ shows(t)
    case D.El{+tag, _, as, ks} <> t:
      "<" ++ tag ++ attrs(as) ++ ">" ++ shows(ks) ++ "</" ++ tag ++ ">" ++ shows(t)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("Backplane polish exact thread link", shows(D.Md.render("[Backplane polish — fast local testing, faster CI, icons and app chrome](backplane://thread/t1792700806-414704)")), "<p><a class=ref href=backplane://thread/t1792700806-414704 data-ref=backplane://thread/t1792700806-414704 data-bare=0 data-value=backplane://thread/t1792700806-414704 onclick=ref-go>Backplane polish — fast local testing, faster CI, icons and app chrome</a></p>")
    C.Check.str("formatted thread label stays a link", shows(D.Md.render("[**Backplane polish**](backplane://thread/t1792700806-414704)")), "<p><a class=ref href=backplane://thread/t1792700806-414704 data-ref=backplane://thread/t1792700806-414704 data-bare=0 data-value=backplane://thread/t1792700806-414704 onclick=ref-go><strong>Backplane polish</strong></a></p>")
    C.Check.str("link inside code stays literal", shows(D.Md.render("`[title](backplane://thread/t1)`")), "<p><code>[title](backplane://thread/t1)</code></p>")
    C.Check.str("unsafe scheme stays literal", shows(D.Md.render("[unsafe](javascript:alert(1))")), "<p>[unsafe](javascript:alert(1))</p>")
    C.Check.str("para", shows(D.Md.render("hello **bold** and `code`")), "<p>hello <strong>bold</strong> and <code>code</code></p>")
    C.Check.str("fence", shows(D.Md.render("a\n```js\nx = 1\n```\nb")), "<p>a</p><div class=codeblock><button class=copy title=Copy data-value=x = 1 onclick=copy>Copy</button><pre><code>x = 1</code></pre></div><p>b</p>")
    C.Check.str("list", shows(D.Md.render("# T\n- one\n- two")), "<h3>T</h3><ul><li>one</li><li>two</li></ul>")
    C.Check.str("stray", shows(D.Md.render("2 * 3 `x")), "<p>2 * 3 `x</p>")
    C.Check.str("html stays text", shows(D.Md.render("<b>hi</b>")), "<p><b>hi</b></p>")
    C.Check.str("table", shows(D.Md.render("Sizes:\n| Part | `R1` |\n|---|:-:|\n| a **b** | 2 |\n|c|\n\nend")),
      "<p>Sizes:</p><table><tr><th>Part</th><th><code>R1</code></th></tr><tr><td>a <strong>b</strong></td><td>2</td></tr><tr><td>c</td></tr></table><p>end</p>")
    C.Check.str("table no head", shows(D.Md.render("| a | b |\n| c | d |")), "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>")
    C.Check.str("lone sep", shows(D.Md.render("|---|")), "<p>|---|</p>")
    C.Check.str("ordered", shows(D.Md.render("1. one\n2. two\n   - sub\n3. three")),
      "<ol><li value=1>one</li><li value=2>two</li></ol><ul><li>sub</li></ul><ol><li value=3>three</li></ol>")
    C.Check.str("not ordered", shows(D.Md.render("3.5 kg\n1.x")), "<p>3.5 kg\n1.x</p>")
    C.Check.str("quote", shows(D.Md.render("> a *b*\n> c")), "<blockquote>a <em>b</em>\nc</blockquote>")
    C.Check.str("hr", shows(D.Md.render("a\n\n---\nb")), "<p>a</p><hr></hr><p>b</p>")
    C.Check.str("deep heads", shows(D.Md.render("#### Four\n#hash")), "<h5>Four</h5><p>#hash</p>")
    C.Check.str("em", shows(D.Md.render("an *em* and **b** and *open")), "<p>an <em>em</em> and <strong>b</strong> and *open</p>")
