import 'package:xml/xml.dart';
import '../../../core/utils/logger.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// OMML → LaTeX CONVERTER  (Phase 3)
// ═══════════════════════════════════════════════════════════════════════════════

/// Converts Office Math Markup Language (OMML) XML to LaTeX strings
/// suitable for rendering with `built-in renderer`.
///
/// Supported constructs:
///   `<m:f>`       → fractions         `\frac{a}{b}`
///   `<m:rad>`     → roots             `\sqrt[n]{x}`
///   `<m:sSup>`    → superscript       `x^{n}`
///   `<m:sSub>`    → subscript         `x_{n}`
///   `<m:sSubSup>` → both              `x_{n}^{m}`
///   `<m:sPre>`    → prescript         `{}_{n}^{m}x`
///   `<m:nary>`    → ∫ ∑ ∏ etc.       `\int_{a}^{b}`
///   `<m:d>`       → delimiters        `\left( \right)`
///   `<m:m>`       → matrices          `\begin{pmatrix}...\end{pmatrix}`
///   `<m:limLow>`  → lower limit       `\lim_{x \to 0}`
///   `<m:limUpp>`  → upper limit       `\overset{n}{x}`
///   `<m:func>`    → function          `\sin x`
///   `<m:acc>`     → accents           `\hat{x}`
///   `<m:bar>`     → over/under-line   `\overline{x}`
///   `<m:groupChr>`→ braces            `\underbrace{x}`
///   `<m:eqArr>`   → aligned equations `\begin{aligned}...\end{aligned}`
///   `<m:borderBox>`→ boxed            `\boxed{x}`
///   Unicode math chars → LaTeX commands (α → \alpha, ∫ → \int, …)
class OmmlParser {
  const OmmlParser();

  /// Converts an `<m:oMath>` XML fragment to LaTeX.
  /// Returns `null` if conversion fails or produces empty output.
  String? toLatex(String ommlXml) {
    if (ommlXml.isEmpty) return null;
    try {
      final doc = XmlDocument.parse(ommlXml);
      final latex = _convertEl(doc.rootElement).trim();
      if (latex.isEmpty) return null;
      AppLogger.debug('OMML→LaTeX: ${latex.length} chars', tag: 'OmmlParser');
      return latex;
    } catch (e) {
      AppLogger.warning('OmmlParser.toLatex failed: $e', tag: 'OmmlParser');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ELEMENT DISPATCH
  // ═══════════════════════════════════════════════════════════════════════════

  String _convertEl(XmlElement el) {
    try {
      return switch (el.localName) {
        // ── Containers ──────────────────────────────────────────────────────
        'oMath'      => _kids(el),
        'oMathPara'  => _kids(el),
        'e'          => _kids(el),  // expression slot
        'num'        => _kids(el),  // fraction numerator
        'den'        => _kids(el),  // fraction denominator
        'sub'        => _kids(el),  // subscript
        'sup'        => _kids(el),  // superscript
        'deg'        => _kids(el),  // root degree
        'lim'        => _kids(el),  // limit expression
        'fName'      => _kids(el),  // function name
        'box'        => _kids(el),
        // ── Math structures ──────────────────────────────────────────────────
        'r'          => _run(el),
        'f'          => _fraction(el),
        'rad'        => _root(el),
        'sSup'       => _sup(el),
        'sSub'       => _sub(el),
        'sSubSup'    => _subSup(el),
        'sPre'       => _preSub(el),
        'nary'       => _nary(el),
        'd'          => _delim(el),
        'm'          => _matrix(el),
        'mr'         => _matrixRow(el),
        'limLow'     => _limLow(el),
        'limUpp'     => _limUpp(el),
        'func'       => _func(el),
        'acc'        => _accent(el),
        'bar'        => _bar(el),
        'borderBox'  => r'\boxed{' + _kids(el) + '}',
        'groupChr'   => _groupChr(el),
        'eqArr'      => _eqArr(el),
        'phant'      => _phant(el),
        // ── Property elements (skip) ─────────────────────────────────────────
        'rPr'        => '',
        'fPr'        => '',
        'radPr'      => '',
        'dPr'        => '',
        'mPr'        => '',
        'mcs'        => '',
        'mc'         => '',
        'naryPr'     => '',
        'sSupPr'     => '',
        'sSubPr'     => '',
        'sSubSupPr'  => '',
        'sPrePr'     => '',
        'accPr'      => '',
        'barPr'      => '',
        'groupChrPr' => '',
        'eqArrPr'    => '',
        'borderBoxPr'=> '',
        'phantPr'    => '',
        'funcPr'     => '',
        'limLowPr'   => '',
        'limUppPr'   => '',
        // ── Unknown: recurse into children ───────────────────────────────────
        _            => _unknown(el),
      };
    } catch (e) {
      AppLogger.warning(
        'OmmlParser: error in <${el.localName}>: $e',
        tag: 'OmmlParser',
      );
      return '';
    }
  }

  /// Concatenates all child element conversions.
  String _kids(XmlElement el) =>
      el.childElements.map(_convertEl).join();

  String _unknown(XmlElement el) {
    // Try to extract any text content so we don't silently lose content
    final text = el.childElements.map(_convertEl).join();
    if (text.isNotEmpty) return text;
    final raw = el.innerText.trim();
    return raw.isNotEmpty ? _mapText(raw, null, null) : '';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT RUN  <m:r>
  // ═══════════════════════════════════════════════════════════════════════════

  String _run(XmlElement r) {
    final rPr = _first(r, 'rPr');
    final styEl = _first(rPr, 'sty');
    final scrEl = _first(rPr, 'scr');
    final norEl = _first(rPr, 'nor');
    final sty   = _mAttr(styEl, 'val'); // b i bi n
    final scr   = _mAttr(scrEl, 'val'); // cal frak double-struck mono
    final nor   = _mAttr(norEl, 'val'); // 1 = normal text (not math)

    // Collect text from all <m:t> elements in this run
    final text = r.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 't')
        .map((e) => e.innerText)
        .join();

    if (text.isEmpty) return '';

    // Normal text (not math variable) — use \text{} or \mathrm{}
    if (nor == '1') return _textRun(text);

    return _mapText(text, sty, scr);
  }

  String _mapText(String text, String? sty, String? scr) {
    if (text.isEmpty) return '';

    // Map each character individually
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      buf.write(_mapChar(ch));
    }
    final mapped = buf.toString();

    // Apply script/style wrappers
    if (scr != null) {
      return switch (scr) {
        'cal'           => '\\mathcal{$mapped}',
        'frak'          => '\\mathfrak{$mapped}',
        'double-struck' => '\\mathbb{$mapped}',
        'mono'          => '\\mathtt{$mapped}',
        'sans-serif'    => '\\mathsf{$mapped}',
        _               => mapped,
      };
    }

    if (sty != null) {
      return switch (sty) {
        'b'  => '\\mathbf{$mapped}',
        'bi' => '\\boldsymbol{$mapped}',
        'n'  => _isKnownFunction(text)
                  ? '\\operatorname{$text}'
                  : (text.length > 1 ? '\\mathrm{$mapped}' : mapped),
        _    => mapped, // 'i' = italic = default math
      };
    }

    // Default: math italic (no wrapper needed)
    return mapped;
  }

  bool _isKnownFunction(String t) => _functions.contains(t.toLowerCase());

  // ═══════════════════════════════════════════════════════════════════════════
  // FRACTION  <m:f>  →  \frac{num}{den}
  // ═══════════════════════════════════════════════════════════════════════════

  String _fraction(XmlElement f) {
    final fPr  = _first(f, 'fPr');
    final type = _mAttr(_first(fPr, 'type'), 'val'); // bar lin noBar skw
    final num  = _group(_kids(_first(f, 'num') ?? f));
    final den  = _group(_kids(_first(f, 'den') ?? f));

    return switch (type) {
      'lin'   => '$num / $den',               // inline a/b style
      'noBar' => '\\binom{$num}{$den}',       // binomial coefficient style
      'skw'   => '$num \\!/ $den',            // skewed fraction
      _       => '\\frac{$num}{$den}',        // default: stacked fraction
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RADICAL  <m:rad>  →  \sqrt[n]{x}  or  \sqrt{x}
  // ═══════════════════════════════════════════════════════════════════════════

  String _root(XmlElement rad) {
    final radPr   = _first(rad, 'radPr');
    final hideEl  = _first(radPr, 'degHide');
    final degHide = _mAttr(hideEl, 'val') == '1' || hideEl?.getAttribute('m:val') == '1';

    final deg = _kids(_first(rad, 'deg') ?? rad).trim();
    final e   = _group(_kids(_first(rad, 'e') ?? rad));

    if (degHide || deg.isEmpty || deg == '2') {
      return '\\sqrt{$e}';
    }
    return '\\sqrt[$deg]{$e}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUB / SUPERSCRIPTS
  // ═══════════════════════════════════════════════════════════════════════════

  String _sup(XmlElement el) {
    final base = _group(_kids(_first(el, 'e') ?? el));
    final sup  = _group(_kids(_first(el, 'sup') ?? el));
    return '{$base}^{$sup}';
  }

  String _sub(XmlElement el) {
    final base = _group(_kids(_first(el, 'e') ?? el));
    final sub  = _group(_kids(_first(el, 'sub') ?? el));
    return '{$base}_{$sub}';
  }

  String _subSup(XmlElement el) {
    final base = _group(_kids(_first(el, 'e') ?? el));
    final sub  = _group(_kids(_first(el, 'sub') ?? el));
    final sup  = _group(_kids(_first(el, 'sup') ?? el));
    return '{$base}_{$sub}^{$sup}';
  }

  String _preSub(XmlElement el) {
    final sub  = _group(_kids(_first(el, 'sub') ?? el));
    final sup  = _group(_kids(_first(el, 'sup') ?? el));
    final base = _kids(_first(el, 'e') ?? el);
    return '{}_{$sub}^{$sup}{$base}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // N-ARY OPERATOR  <m:nary>  →  \int \sum \prod etc.
  // ═══════════════════════════════════════════════════════════════════════════

  String _nary(XmlElement el) {
    final pr       = _first(el, 'naryPr');
    final chrEl    = _first(pr, 'chr');
    final char     = _mAttr(chrEl, 'val') ?? '∑';
    final limLoc   = _mAttr(_first(pr, 'limLoc'), 'val') ?? 'undOvr';
    final subHide  = _mAttr(_first(pr, 'subHide'), 'val') == '1';
    final supHide  = _mAttr(_first(pr, 'supHide'), 'val') == '1';
    final growEl   = _first(pr, 'grow');
    final grow     = _mAttr(growEl, 'val') != '0';

    final cmd    = _naryChar(char);
    final limits = (limLoc == 'undOvr') ? '\\limits' : '';
    final sub    = subHide ? '' : '_{${_kids(_first(el, 'sub') ?? el)}}';
    final sup    = supHide ? '' : '^{${_kids(_first(el, 'sup') ?? el)}}';
    final body   = _kids(_first(el, 'e') ?? el);

    return '$cmd$limits$sub$sup{$body}';
  }

  String _naryChar(String ch) => switch (ch) {
    '∫'  => r'\int',
    '∬'  => r'\iint',
    '∭'  => r'\iiint',
    '∮'  => r'\oint',
    '∯'  => r'\oiint',
    '∰'  => r'\oiiint',
    '∑'  => r'\sum',
    '∏'  => r'\prod',
    '∐'  => r'\coprod',
    '⋂'  => r'\bigcap',
    '⋃'  => r'\bigcup',
    '⋀'  => r'\bigwedge',
    '⋁'  => r'\bigvee',
    '⨁'  => r'\bigoplus',
    '⨂'  => r'\bigotimes',
    '⨀'  => r'\bigodot',
    '⨃'  => r'\biguplus',
    _    => _mapChar(ch),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // DELIMITER  <m:d>  →  \left( \right)
  // ═══════════════════════════════════════════════════════════════════════════

  String _delim(XmlElement el) {
    final pr     = _first(el, 'dPr');
    final beg    = _mAttr(_first(pr, 'begChr'), 'val') ?? '(';
    final end    = _mAttr(_first(pr, 'endChr'), 'val') ?? ')';
    final sep    = _mAttr(_first(pr, 'sepChr'), 'val') ?? ',';

    final lDel = _delimCmd(beg, isLeft: true);
    final rDel = _delimCmd(end, isLeft: false);

    // All <m:e> children separated by sep
    final eEls = el.childElements.where((c) => c.localName == 'e').toList();
    if (eEls.isEmpty) return '$lDel$rDel';

    final content = eEls.map((e) => _kids(e)).join(' ${_mapChar(sep)} ');
    return '$lDel $content $rDel';
  }

  String _delimCmd(String ch, {required bool isLeft}) {
    final side = isLeft ? r'\left' : r'\right';
    if (ch.isEmpty) return '$side.';  // invisible delimiter
    return switch (ch) {
      '('  => '$side(',
      ')'  => '$side)',
      '['  => '$side[',
      ']'  => '$side]',
      '{'  => '$side\\{',
      '}'  => '$side\\}',
      '|'  => '$side|',
      '‖'  => '$side\\|',
      '⌈'  => '$side\\lceil',
      '⌉'  => '$side\\rceil',
      '⌊'  => '$side\\lfloor',
      '⌋'  => '$side\\rfloor',
      '⟨'  => '$side\\langle',
      '⟩'  => '$side\\rangle',
      '⌉'  => '$side\\rceil',
      '/'  => '$side/',
      '\\' => '$side\\backslash',
      _    => '$side.',  // unknown → invisible
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MATRIX  <m:m>
  // ═══════════════════════════════════════════════════════════════════════════

  String _matrix(XmlElement el) {
    // Determine environment from enclosing delimiter (heuristic: pmatrix default)
    // In practice, the delimiter wraps the <m:m>, so we just produce the inner matrix
    final rows = el.childElements
        .where((c) => c.localName == 'mr')
        .map(_matrixRow)
        .join(r' \\ ');
    return r'\begin{matrix}' + rows + r'\end{matrix}';
  }

  String _matrixRow(XmlElement mr) {
    final cols = mr.childElements
        .where((c) => c.localName == 'e')
        .map((e) => _kids(e))
        .join(' & ');
    return cols;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIMITS
  // ═══════════════════════════════════════════════════════════════════════════

  String _limLow(XmlElement el) {
    final base = _kids(_first(el, 'e') ?? el);
    final lim  = _kids(_first(el, 'lim') ?? el);
    return '{$base}_{$lim}';
  }

  String _limUpp(XmlElement el) {
    final base = _kids(_first(el, 'e') ?? el);
    final lim  = _kids(_first(el, 'lim') ?? el);
    return '\\overset{$lim}{$base}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FUNCTION  <m:func>  →  \sin x
  // ═══════════════════════════════════════════════════════════════════════════

  String _func(XmlElement el) {
    final name = _kids(_first(el, 'fName') ?? el).trim();
    final body = _kids(_first(el, 'e') ?? el);
    // If name already starts with \, use as-is
    if (name.startsWith(r'\')) return '$name{$body}';
    if (_functions.contains(name)) return '\\$name{$body}';
    return '\\operatorname{$name}{$body}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCENT  <m:acc>  →  \hat{x}  etc.
  // ═══════════════════════════════════════════════════════════════════════════

  String _accent(XmlElement el) {
    final pr  = _first(el, 'accPr');
    final chr = _mAttr(_first(pr, 'chr'), 'val') ?? '';
    final body = _group(_kids(_first(el, 'e') ?? el));

    return switch (chr) {
      '\u0302' || '^'  => '\\hat{$body}',
      '\u0303' || '~'  => '\\tilde{$body}',
      '\u0307'         => '\\dot{$body}',
      '\u0308'         => '\\ddot{$body}',
      '\u0309'         => '\\hat{$body}',
      '\u030A'         => '\\mathring{$body}',
      '\u0300'         => '\\grave{$body}',
      '\u0301'         => '\\acute{$body}',
      '\u0304'         => '\\bar{$body}',
      '\u0306'         => '\\breve{$body}',
      '\u030C'         => '\\check{$body}',
      '\u20D7' || '⃗'  => '\\vec{$body}',
      '\u0305'         => '\\bar{$body}',   // overline combining
      '̈'              => '\\ddot{$body}',
      _               => '\\hat{$body}',    // safe fallback
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAR  <m:bar>  →  \overline  or  \underline
  // ═══════════════════════════════════════════════════════════════════════════

  String _bar(XmlElement el) {
    final pr  = _first(el, 'barPr');
    final pos = _mAttr(_first(pr, 'pos'), 'val') ?? 'top';
    final body = _group(_kids(_first(el, 'e') ?? el));
    return pos == 'bot' ? '\\underline{$body}' : '\\overline{$body}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP CHARACTER  <m:groupChr>  →  \underbrace  \overbrace
  // ═══════════════════════════════════════════════════════════════════════════

  String _groupChr(XmlElement el) {
    final pr  = _first(el, 'groupChrPr');
    final chr = _mAttr(_first(pr, 'chr'),    'val') ?? '⏟';
    final pos = _mAttr(_first(pr, 'pos'),    'val') ?? 'bot';
    final body = _group(_kids(_first(el, 'e') ?? el));

    return switch (chr) {
      '⏟' || '⏜'  => pos == 'bot' ? '\\underbrace{$body}' : '\\overbrace{$body}',
      '⏞' || '⌣'  => '\\overbrace{$body}',
      _            => pos == 'bot' ? '\\underbrace{$body}' : '\\overbrace{$body}',
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EQUATION ARRAY  <m:eqArr>  →  \begin{aligned}…\end{aligned}
  // ═══════════════════════════════════════════════════════════════════════════

  String _eqArr(XmlElement el) {
    final rows = el.childElements
        .where((c) => c.localName == 'e')
        .map((e) => _kids(e))
        .join(r' \\ ');
    return r'\begin{aligned}' + rows + r'\end{aligned}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHANTOM  <m:phant>  →  invisible spacing
  // ═══════════════════════════════════════════════════════════════════════════

  String _phant(XmlElement el) {
    final pr      = _first(el, 'phantPr');
    final showEl  = _first(pr, 'show');
    final show    = _mAttr(showEl, 'val') != '0';
    final body    = _kids(_first(el, 'e') ?? el);
    return show ? body : '\\phantom{$body}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHARACTER MAPPING  Unicode → LaTeX
  // ═══════════════════════════════════════════════════════════════════════════

  String _mapChar(String ch) => _charMap[ch] ?? ch;

  // Wraps in braces only when necessary (multi-char output)
  String _group(String latex) {
    if (latex.length <= 1) return latex;
    // Already grouped
    if (latex.startsWith('{') && latex.endsWith('}')) return latex;
    // Single command like \alpha — no group needed for single-char arguments
    // but group for safety in sub/superscript contexts
    return '{$latex}';
  }

  String _escapeTex(String text) {
    return text
        .replaceAll(r'\', r'\textbackslash{}')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('#', r'\#')
        .replaceAll('%', r'\%')
        .replaceAll('&', r'\&');
  }

  /// Wraps [text] for use inside LaTeX \text{}.
  /// flutter_math_fork only supports ASCII in math mode — non-ASCII chars
  /// (Vietnamese, CJK…) cause a parse error. We detect non-ASCII and embed
  /// sentinel §P§…§E§ that equation_renderer replaces with a plain Text span.
  String _textRun(String text) {
    // The equation renderer displays LaTeX source as monospace text (not
    // rendered math). For pure ASCII, wrap with \text{} for readability.
    // For non-ASCII (Vietnamese, etc.), keep the raw Unicode so it renders
    // correctly in the monospace view without garbled escape sequences.
    final hasNonAscii = text.codeUnits.any((c) => c > 127);
    if (!hasNonAscii) return '\\text{${_escapeTex(text)}}';
    return '\\text{$text}';
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // XML HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  XmlElement? _first(XmlElement? parent, String localName) {
    if (parent == null) return null;
    for (final child in parent.childElements) {
      if (child.localName == localName) return child;
    }
    return null;
  }

  String? _mAttr(XmlElement? el, String name) {
    if (el == null) return null;
    for (final attr in el.attributes) {
      if (attr.localName == name) return attr.value;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATIC DATA TABLES
  // ═══════════════════════════════════════════════════════════════════════════

  static const Set<String> _functions = {
    'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
    'sinh', 'cosh', 'tanh', 'coth',
    'arcsin', 'arccos', 'arctan', 'arccot',
    'asin', 'acos', 'atan',
    'log', 'ln', 'lg', 'exp',
    'lim', 'sup', 'inf', 'max', 'min',
    'det', 'ker', 'dim', 'rank', 'tr', 'sgn',
    'gcd', 'lcm', 'deg',
    'Pr', 'arg', 'Re', 'Im',
    'mod', 'div',
  };

  static const Map<String, String> _charMap = {
    // ── Greek lowercase ──────────────────────────────────────────────────────
    'α': r'\alpha',    'β': r'\beta',    'γ': r'\gamma',   'δ': r'\delta',
    'ε': r'\varepsilon','ζ': r'\zeta',   'η': r'\eta',     'θ': r'\theta',
    'ι': r'\iota',    'κ': r'\kappa',   'λ': r'\lambda',  'μ': r'\mu',
    'ν': r'\nu',      'ξ': r'\xi',      'π': r'\pi',      'ρ': r'\rho',
    'σ': r'\sigma',   'τ': r'\tau',     'υ': r'\upsilon', 'φ': r'\varphi',
    'χ': r'\chi',     'ψ': r'\psi',     'ω': r'\omega',
    // variants
    'ϕ': r'\phi',     'ϵ': r'\epsilon', 'ϑ': r'\vartheta','ϰ': r'\varkappa',
    'ϱ': r'\varrho',  'ς': r'\varsigma','ϖ': r'\varpi',
    // ── Greek uppercase ──────────────────────────────────────────────────────
    'Γ': r'\Gamma',   'Δ': r'\Delta',   'Θ': r'\Theta',   'Λ': r'\Lambda',
    'Ξ': r'\Xi',      'Π': r'\Pi',      'Σ': r'\Sigma',   'Υ': r'\Upsilon',
    'Φ': r'\Phi',     'Ψ': r'\Psi',     'Ω': r'\Omega',
    // ── Arithmetic ───────────────────────────────────────────────────────────
    '×': r'\times',   '÷': r'\div',     '±': r'\pm',      '∓': r'\mp',
    '·': r'\cdot',    '∙': r'\cdot',    '⋅': r'\cdot',    '∗': r'\ast',
    '∘': r'\circ',    '⊕': r'\oplus',   '⊗': r'\otimes',  '⊖': r'\ominus',
    '⊙': r'\odot',    '⊞': r'\boxplus',
    // ── Relations ────────────────────────────────────────────────────────────
    '≤': r'\leq',     '≥': r'\geq',     '≠': r'\neq',     '≈': r'\approx',
    '≡': r'\equiv',   '∼': r'\sim',     '≃': r'\simeq',   '≅': r'\cong',
    '≪': r'\ll',      '≫': r'\gg',      '≺': r'\prec',    '≻': r'\succ',
    '≼': r'\preceq',  '≽': r'\succeq',  '∝': r'\propto',  '⊢': r'\vdash',
    '⊨': r'\models',  '≲': r'\lesssim', '≳': r'\gtrsim',
    '⩽': r'\leqslant','⩾': r'\geqslant',
    '≦': r'\leqq',    '≧': r'\geqq',
    // ── Set theory ───────────────────────────────────────────────────────────
    '∈': r'\in',      '∉': r'\notin',   '⊂': r'\subset',  '⊃': r'\supset',
    '⊆': r'\subseteq','⊇': r'\supseteq','⊄': r'\not\subset',
    '∩': r'\cap',     '∪': r'\cup',     '∅': r'\emptyset','∖': r'\setminus',
    '△': r'\triangle','⊂⃝': r'\circledS',
    '⋂': r'\bigcap',  '⋃': r'\bigcup',
    // ── Logic ────────────────────────────────────────────────────────────────
    '∀': r'\forall',  '∃': r'\exists',  '∄': r'\nexists', '¬': r'\neg',
    '∧': r'\wedge',   '∨': r'\vee',     '⊤': r'\top',     '⊥': r'\perp',
    '⊻': r'\veebar',
    // ── Calculus / Analysis ──────────────────────────────────────────────────
    '∂': r'\partial', '∇': r'\nabla',   '∞': r'\infty',   'ℓ': r'\ell',
    '∫': r'\int',     '∬': r'\iint',    '∭': r'\iiint',   '∮': r'\oint',
    '∑': r'\sum',     '∏': r'\prod',    '∐': r'\coprod',
    '√': r'\surd',
    // ── Arrows ───────────────────────────────────────────────────────────────
    '→': r'\rightarrow',      '←': r'\leftarrow',
    '↔': r'\leftrightarrow',  '↑': r'\uparrow',
    '↓': r'\downarrow',       '↕': r'\updownarrow',
    '⇒': r'\Rightarrow',      '⇐': r'\Leftarrow',
    '⇔': r'\Leftrightarrow',  '⇑': r'\Uparrow',
    '⇓': r'\Downarrow',       '⇕': r'\Updownarrow',
    '⟹': r'\Longrightarrow',  '⟺': r'\Longleftrightarrow',
    '⟶': r'\longrightarrow',  '⟵': r'\longleftarrow',
    '↦': r'\mapsto',          '⟼': r'\longmapsto',
    '↪': r'\hookrightarrow',  '↩': r'\hookleftarrow',
    '↠': r'\twoheadrightarrow','↞': r'\twoheadleftarrow',
    '⇌': r'\rightleftharpoons','⇋': r'\leftrightharpoons',
    // ── Brackets ─────────────────────────────────────────────────────────────
    '⌈': r'\lceil',   '⌉': r'\rceil',   '⌊': r'\lfloor',  '⌋': r'\rfloor',
    '⟨': r'\langle',  '⟩': r'\rangle',  '⌜': r'\ulcorner','⌝': r'\urcorner',
    '⌞': r'\llcorner','⌟': r'\lrcorner',
    // ── Dots ─────────────────────────────────────────────────────────────────
    '…': r'\ldots',   '⋯': r'\cdots',   '⋮': r'\vdots',   '⋱': r'\ddots',
    '⋰': r'\iddots',
    // ── Number sets ──────────────────────────────────────────────────────────
    'ℝ': r'\mathbb{R}','ℕ': r'\mathbb{N}','ℤ': r'\mathbb{Z}',
    'ℚ': r'\mathbb{Q}','ℂ': r'\mathbb{C}','ℙ': r'\mathbb{P}',
    'ℍ': r'\mathbb{H}','𝔽': r'\mathbb{F}',
    // ── Special symbols ───────────────────────────────────────────────────────
    '∥': r'\parallel','∦': r'\nparallel','∠': r'\angle',   '∡': r'\measuredangle',
    '□': r'\square',   '◇': r'\diamond', '★': r'\bigstar',
    '†': r'\dagger',  '‡': r'\ddagger',  '§': r'\S',       '¶': r'\P',
    '℃': r'^\circ\mathrm{C}','°': r'^\circ',
    '′': "'",         '″': "''",          '‴': "'''",
    '∴': r'\therefore','∵': r'\because',
    '♠': r'\spadesuit','♣': r'\clubsuit','♥': r'\heartsuit','♦': r'\diamondsuit',
    // ── Half-width fractions ─────────────────────────────────────────────────
    '½': r'\frac{1}{2}','⅓': r'\frac{1}{3}','⅔': r'\frac{2}{3}',
    '¼': r'\frac{1}{4}','¾': r'\frac{3}{4}','⅛': r'\frac{1}{8}',
    // ── Subscript/superscript digits (Unicode block) ─────────────────────────
    '⁰': r'^{0}', '¹': r'^{1}', '²': r'^{2}', '³': r'^{3}', '⁴': r'^{4}',
    '⁵': r'^{5}', '⁶': r'^{6}', '⁷': r'^{7}', '⁸': r'^{8}', '⁹': r'^{9}',
    '₀': r'_{0}', '₁': r'_{1}', '₂': r'_{2}', '₃': r'_{3}', '₄': r'_{4}',
    '₅': r'_{5}', '₆': r'_{6}', '₇': r'_{7}', '₈': r'_{8}', '₉': r'_{9}',
    // ── Math italic Unicode block → plain letters ────────────────────────────
    '𝑎': 'a', '𝑏': 'b', '𝑐': 'c', '𝑑': 'd', '𝑒': 'e', '𝑓': 'f', '𝑔': 'g',
    '𝑥': 'x', '𝑦': 'y', '𝑧': 'z', '𝑛': 'n', '𝑚': 'm', '𝑘': 'k', '𝑗': 'j',
    '𝑖': 'i', '𝑝': 'p', '𝑞': 'q', '𝑟': 'r', '𝑠': 's', '𝑡': 't', '𝑢': 'u',
    '𝑣': 'v', '𝑤': 'w', '𝐴': 'A', '𝐵': 'B', '𝐶': 'C', '𝐷': 'D',
  };
}
