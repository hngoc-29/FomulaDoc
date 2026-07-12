import 'package:flutter_test/flutter_test.dart';
import 'package:formuladoc/data/parsers/omml/omml_parser.dart';

// ─── Helper ───────────────────────────────────────────────────────────────────

const String _ns =
    'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"';

String _oMath(String inner) => '<m:oMath $_ns>$inner</m:oMath>';

String _r(String text, {String? sty}) {
  final rPr = sty != null
      ? '<m:rPr><m:sty m:val="$sty"/></m:rPr>'
      : '';
  return '<m:r>$rPr<m:t>$text</m:t></m:r>';
}

// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  late OmmlParser parser;

  setUp(() => parser = const OmmlParser());

  // ── Null / empty safety ────────────────────────────────────────────────────

  group('Safety', () {
    test('empty string returns null', () {
      expect(parser.toLatex(''), isNull);
    });

    test('invalid XML returns null', () {
      expect(parser.toLatex('<not valid xml'), isNull);
    });

    test('empty oMath returns null', () {
      expect(parser.toLatex(_oMath('')), isNull);
    });
  });

  // ── Text run ──────────────────────────────────────────────────────────────

  group('Text runs', () {
    test('plain letter', () {
      final r = parser.toLatex(_oMath(_r('x')));
      expect(r, contains('x'));
    });

    test('Greek letter alpha', () {
      final r = parser.toLatex(_oMath(_r('α')));
      expect(r, contains(r'\alpha'));
    });

    test('Greek letter omega', () {
      final r = parser.toLatex(_oMath(_r('ω')));
      expect(r, contains(r'\omega'));
    });

    test('infinity symbol', () {
      final r = parser.toLatex(_oMath(_r('∞')));
      expect(r, contains(r'\infty'));
    });

    test('partial derivative', () {
      final r = parser.toLatex(_oMath(_r('∂')));
      expect(r, contains(r'\partial'));
    });

    test('summation symbol', () {
      final r = parser.toLatex(_oMath(_r('∑')));
      expect(r, contains(r'\sum'));
    });

    test('integral symbol', () {
      final r = parser.toLatex(_oMath(_r('∫')));
      expect(r, contains(r'\int'));
    });

    test('bold run wraps in \\mathbf', () {
      final r = parser.toLatex(_oMath(_r('v', sty: 'b')));
      expect(r, contains(r'\mathbf'));
    });

    test('multi-char normal run → \\mathrm or \\operatorname', () {
      final r = parser.toLatex(_oMath(_r('sin', sty: 'n')));
      expect(r, anyOf(contains(r'\sin'), contains(r'\operatorname'), contains(r'\mathrm')));
    });

    test('complex inequalities', () {
      expect(parser.toLatex(_oMath(_r('≤'))), contains(r'\leq'));
      expect(parser.toLatex(_oMath(_r('≥'))), contains(r'\geq'));
      expect(parser.toLatex(_oMath(_r('≠'))), contains(r'\neq'));
    });

    test('set membership', () {
      expect(parser.toLatex(_oMath(_r('∈'))), contains(r'\in'));
      expect(parser.toLatex(_oMath(_r('∉'))), contains(r'\notin'));
    });

    test('arrows', () {
      expect(parser.toLatex(_oMath(_r('→'))), contains(r'\rightarrow'));
      expect(parser.toLatex(_oMath(_r('⇒'))), contains(r'\Rightarrow'));
      expect(parser.toLatex(_oMath(_r('⟺'))), contains(r'\Longleftrightarrow'));
    });

    test('real numbers ℝ → \\mathbb{R}', () {
      final r = parser.toLatex(_oMath(_r('ℝ')));
      expect(r, contains(r'\mathbb{R}'));
    });
  });

  // ── Fraction ──────────────────────────────────────────────────────────────

  group('Fractions', () {
    String _frac(String num, String den) =>
        '<m:f $_ns>'
        '<m:num><m:r><m:t>$num</m:t></m:r></m:num>'
        '<m:den><m:r><m:t>$den</m:t></m:r></m:den>'
        '</m:f>';

    test('simple fraction a/b', () {
      final r = parser.toLatex(_oMath(_frac('a', 'b')));
      expect(r, contains(r'\frac'));
      expect(r, contains('a'));
      expect(r, contains('b'));
    });

    test('fraction 1/2', () {
      final r = parser.toLatex(_oMath(_frac('1', '2')));
      expect(r, equals(r'\frac{1}{2}'));
    });

    test('nested: fraction with Greek', () {
      final r = parser.toLatex(_oMath(_frac('α', 'β')));
      expect(r, contains(r'\frac'));
      expect(r, contains(r'\alpha'));
      expect(r, contains(r'\beta'));
    });
  });

  // ── Root ──────────────────────────────────────────────────────────────────

  group('Roots', () {
    test('square root (degHide=1)', () {
      const xml = '<m:rad $_ns>'
          '<m:radPr><m:degHide m:val="1"/></m:radPr>'
          '<m:deg/>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '</m:rad>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains(r'\sqrt{x}'));
    });

    test('nth root', () {
      const xml = '<m:rad $_ns>'
          '<m:radPr><m:degHide m:val="0"/></m:radPr>'
          '<m:deg><m:r><m:t>3</m:t></m:r></m:deg>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '</m:rad>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains(r'\sqrt[3]{x}'));
    });
  });

  // ── Superscript / Subscript ───────────────────────────────────────────────

  group('Super/Subscripts', () {
    test('superscript x^n', () {
      const xml = '<m:sSup $_ns>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '<m:sup><m:r><m:t>n</m:t></m:r></m:sup>'
          '</m:sSup>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains('^'));
      expect(r, contains('x'));
      expect(r, contains('n'));
    });

    test('subscript x_n', () {
      const xml = '<m:sSub $_ns>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '<m:sub><m:r><m:t>n</m:t></m:r></m:sub>'
          '</m:sSub>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains('_'));
      expect(r, contains('x'));
      expect(r, contains('n'));
    });

    test('sub+superscript x_n^m', () {
      const xml = '<m:sSubSup $_ns>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '<m:sub><m:r><m:t>n</m:t></m:r></m:sub>'
          '<m:sup><m:r><m:t>m</m:t></m:r></m:sup>'
          '</m:sSubSup>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains('_'));
      expect(r, contains('^'));
    });

    test('e^2 (Euler number)', () {
      const xml = '<m:sSup $_ns>'
          '<m:e><m:r><m:t>e</m:t></m:r></m:e>'
          '<m:sup><m:r><m:t>2</m:t></m:r></m:sup>'
          '</m:sSup>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, isNotNull);
      expect(r, contains('^'));
    });
  });

  // ── N-ary (integral / sum / product) ─────────────────────────────────────

  group('N-ary operators', () {
    String _nary(String chr, String sub, String sup, String body) =>
        '<m:nary $_ns>'
        '<m:naryPr><m:chr m:val="$chr"/></m:naryPr>'
        '<m:sub><m:r><m:t>$sub</m:t></m:r></m:sub>'
        '<m:sup><m:r><m:t>$sup</m:t></m:r></m:sup>'
        '<m:e><m:r><m:t>$body</m:t></m:r></m:e>'
        '</m:nary>';

    test('integral from a to b', () {
      final r = parser.toLatex(_oMath(_nary('∫', 'a', 'b', 'f(x)')));
      expect(r, contains(r'\int'));
      expect(r, contains('a'));
      expect(r, contains('b'));
    });

    test('summation from 1 to n', () {
      final r = parser.toLatex(_oMath(_nary('∑', '1', 'n', 'i')));
      expect(r, contains(r'\sum'));
    });

    test('product operator', () {
      final r = parser.toLatex(_oMath(_nary('∏', '1', 'n', 'a_i')));
      expect(r, contains(r'\prod'));
    });
  });

  // ── Delimiters ────────────────────────────────────────────────────────────

  group('Delimiters', () {
    String _delim(String beg, String end, String content) =>
        '<m:d $_ns>'
        '<m:dPr>'
        '<m:begChr m:val="$beg"/>'
        '<m:endChr m:val="$end"/>'
        '</m:dPr>'
        '<m:e><m:r><m:t>$content</m:t></m:r></m:e>'
        '</m:d>';

    test('parentheses (x)', () {
      final r = parser.toLatex(_oMath(_delim('(', ')', 'x')));
      expect(r, contains(r'\left('));
      expect(r, contains(r'\right)'));
    });

    test('square brackets [x]', () {
      final r = parser.toLatex(_oMath(_delim('[', ']', 'x')));
      expect(r, contains(r'\left['));
      expect(r, contains(r'\right]'));
    });

    test('curly braces {x}', () {
      final r = parser.toLatex(_oMath(_delim('{', '}', 'x')));
      expect(r, contains(r'\left\{'));
      expect(r, contains(r'\right\}'));
    });

    test('absolute value |x|', () {
      final r = parser.toLatex(_oMath(_delim('|', '|', 'x')));
      expect(r, contains(r'\left|'));
      expect(r, contains(r'\right|'));
    });

    test('angle brackets ⟨x⟩', () {
      final r = parser.toLatex(_oMath(_delim('⟨', '⟩', 'x')));
      expect(r, contains(r'\langle'));
      expect(r, contains(r'\rangle'));
    });
  });

  // ── Accents ───────────────────────────────────────────────────────────────

  group('Accents', () {
    String _acc(String chr, String base) =>
        '<m:acc $_ns>'
        '<m:accPr><m:chr m:val="$chr"/></m:accPr>'
        '<m:e><m:r><m:t>$base</m:t></m:r></m:e>'
        '</m:acc>';

    test('hat accent', () {
      final r = parser.toLatex(_oMath(_acc('\u0302', 'x')));
      expect(r, contains(r'\hat'));
    });

    test('tilde accent', () {
      final r = parser.toLatex(_oMath(_acc('\u0303', 'x')));
      expect(r, contains(r'\tilde'));
    });

    test('vector arrow', () {
      final r = parser.toLatex(_oMath(_acc('\u20D7', 'v')));
      expect(r, contains(r'\vec'));
    });
  });

  // ── Bar ───────────────────────────────────────────────────────────────────

  group('Bar (over/underline)', () {
    test('overline (top)', () {
      const xml = '<m:bar $_ns>'
          '<m:barPr><m:pos m:val="top"/></m:barPr>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '</m:bar>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains(r'\overline'));
    });

    test('underline (bot)', () {
      const xml = '<m:bar $_ns>'
          '<m:barPr><m:pos m:val="bot"/></m:barPr>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '</m:bar>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains(r'\underline'));
    });
  });

  // ── Matrix ────────────────────────────────────────────────────────────────

  group('Matrix', () {
    test('2×2 matrix', () {
      const xml = '<m:m $_ns>'
          '<m:mr><m:e><m:r><m:t>a</m:t></m:r></m:e>'
          '<m:e><m:r><m:t>b</m:t></m:r></m:e></m:mr>'
          '<m:mr><m:e><m:r><m:t>c</m:t></m:r></m:e>'
          '<m:e><m:r><m:t>d</m:t></m:r></m:e></m:mr>'
          '</m:m>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains(r'\begin{matrix}'));
      expect(r, contains(r'\end{matrix}'));
      expect(r, contains('&'));
      expect(r, contains(r'\\'));
    });
  });

  // ── Complex compound equations ────────────────────────────────────────────

  group('Compound equations', () {
    test('quadratic formula structure', () {
      // x = (-b ± √(b²-4ac)) / 2a  — simplified structure
      const numXml = '<m:r><m:t>-b</m:t></m:r>';
      const denXml = '<m:r><m:t>2a</m:t></m:r>';
      final fracXml = '<m:f $_ns>'
          '<m:num>$numXml</m:num>'
          '<m:den>$denXml</m:den>'
          '</m:f>';
      final r = parser.toLatex(_oMath(fracXml));
      expect(r, contains(r'\frac'));
      expect(r, isNotNull);
    });

    test('E = mc^2 structure', () {
      const xml = '<m:sSup $_ns>'
          '<m:e><m:r><m:t>mc</m:t></m:r></m:e>'
          '<m:sup><m:r><m:t>2</m:t></m:r></m:sup>'
          '</m:sSup>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, isNotNull);
      expect(r, contains('^{2}'));
    });

    test('limit as x→0', () {
      const xml = '<m:limLow $_ns>'
          '<m:e><m:r><m:rPr><m:sty m:val="n"/></m:rPr><m:t>lim</m:t></m:r></m:e>'
          '<m:lim><m:r><m:t>x</m:t></m:r>'
          '<m:r><m:t>→</m:t></m:r>'
          '<m:r><m:t>0</m:t></m:r>'
          '</m:lim>'
          '</m:limLow>';
      final r = parser.toLatex(_oMath(xml));
      expect(r, contains('lim'));
      expect(r, contains(r'\rightarrow'));
      expect(r, contains('0'));
    });

    test('nested fraction inside superscript', () {
      const fracXml = '<m:f $_ns>'
          '<m:num><m:r><m:t>1</m:t></m:r></m:num>'
          '<m:den><m:r><m:t>2</m:t></m:r></m:den>'
          '</m:f>';
      const supXml = '<m:sSup $_ns>'
          '<m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '<m:sup>$fracXml</m:sup>'
          '</m:sSup>';
      final r = parser.toLatex(_oMath(supXml));
      expect(r, isNotNull);
      expect(r, contains(r'\frac'));
      expect(r, contains('^'));
    });
  });

  // ── Character mapping completeness ────────────────────────────────────────

  group('Character mapping', () {
    final testCases = {
      '±': r'\pm',    '∓': r'\mp',    '×': r'\times',  '÷': r'\div',
      '≡': r'\equiv', '∼': r'\sim',   '≅': r'\cong',   '≈': r'\approx',
      '⊂': r'\subset','⊃': r'\supset','∩': r'\cap',    '∪': r'\cup',
      '∀': r'\forall','∃': r'\exists','¬': r'\neg',    '∧': r'\wedge',
      '↑': r'\uparrow','↓': r'\downarrow',
      'ℕ': r'\mathbb{N}', 'ℤ': r'\mathbb{Z}', 'ℂ': r'\mathbb{C}',
    };

    testCases.forEach((unicode, expectedLatex) {
      test('$unicode → $expectedLatex', () {
        final result = parser.toLatex(_oMath(_r(unicode)));
        expect(result, isNotNull, reason: 'Should not return null for $unicode');
        expect(result!, contains(expectedLatex),
            reason: 'Expected $unicode → $expectedLatex, got: $result');
      });
    });
  });
}
