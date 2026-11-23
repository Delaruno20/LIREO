import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'flow_document.dart';

/// Convertit du HTML/XHTML en blocs [FlowBlock].
///
/// Utilisé par les adaptateurs EPUB, HTML, Markdown et MOBI. Le CSS n'est pas
/// interprété en entier : seules les intentions utiles à la lecture sont
/// conservées (gras, italique, centrage, titres, citations, listes, images).
class HtmlFlowConverter {
  HtmlFlowConverter({String Function(String src)? resolveImage}) : _resolveImage = resolveImage ?? ((s) => s);

  final String Function(String src) _resolveImage;

  final _blocks = <FlowBlock>[];
  final _runs = <InlineRun>[];
  final _pendingAnchors = <String>[];
  final _anchors = <(String, int)>[];
  var _runLength = 0;
  var _lastWasSpace = true;

  static const _skip = {'script', 'style', 'head', 'title', 'noscript', 'template', 'iframe', 'object', 'math'};
  static const _blockTags = {
    'p', 'div', 'section', 'article', 'header', 'footer', 'aside', 'nav', 'main', 'body', 'figure', 'figcaption',
    'table', 'thead', 'tbody', 'tr', 'ul', 'ol', 'dl', 'dt', 'dd', 'li', 'blockquote', 'pre', 'center', 'address',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hgroup', 'td', 'th', 'caption', 'details', 'summary', 'poem', 'stanza',
  };

  static List<FlowBlock> parse(String source, {String Function(String src)? resolveImage}) {
    final doc = html_parser.parse(source);
    return HtmlFlowConverter(resolveImage: resolveImage).convert(doc.body ?? doc.documentElement!);
  }

  List<FlowBlock> convert(dom.Node root) {
    _visit(root, const _Ctx());
    _flush(const _Ctx());
    return List.of(_blocks);
  }

  void _visit(dom.Node node, _Ctx ctx) {
    if (node is dom.Text) {
      _appendText(node.text, ctx);
      return;
    }
    if (node is! dom.Element) {
      for (final c in node.nodes) {
        _visit(c, ctx);
      }
      return;
    }
    final tag = node.localName?.toLowerCase() ?? '';
    if (_skip.contains(tag)) return;

    final id = node.attributes['id'] ?? node.attributes['name'];
    if (id != null && id.isNotEmpty) _pendingAnchors.add(id);

    switch (tag) {
      case 'img':
      case 'image':
        final src = node.attributes['src'] ??
            node.attributes['xlink:href'] ??
            node.attributes['href'] ??
            _attrEndingWith(node, 'href');
        if (src != null && src.isNotEmpty) {
          _flush(ctx);
          _blocks.add(ImageBlock(_resolveImage(src), alt: node.attributes['alt'] ?? ''));
        }
        return;
      case 'br':
        _appendRaw('\n', ctx);
        _lastWasSpace = true;
        return;
      case 'hr':
        _flush(ctx);
        _blocks.add(RuleBlock());
        return;
    }

    var next = ctx.withInline(tag, node.attributes['style'], node.attributes['href']);
    final isBlock = _blockTags.contains(tag) || _styleIsBlock(node.attributes['style']);
    if (!isBlock) {
      for (final c in node.nodes) {
        _visit(c, next);
      }
      return;
    }

    _flush(ctx);
    next = next.withBlock(tag, node);
    if (tag == 'li') {
      final parent = node.parent;
      final ordered = parent?.localName == 'ol';
      final index = parent == null ? 0 : parent.children.where((e) => e.localName == 'li').toList().indexOf(node);
      _appendRaw(ordered ? '${index + 1}. ' : '•  ', next);
    }
    for (final c in node.nodes) {
      _visit(c, next);
    }
    _flush(next);
  }

  String? _attrEndingWith(dom.Element e, String suffix) {
    for (final entry in e.attributes.entries) {
      if (entry.key.toString().endsWith(suffix)) return entry.value;
    }
    return null;
  }

  static bool _styleIsBlock(String? style) => style != null && style.contains(RegExp(r'display\s*:\s*block'));

  static final _ws = RegExp(r'\s+');

  void _appendText(String text, _Ctx ctx) {
    if (ctx.preformatted) {
      _appendRaw(text, ctx);
      return;
    }
    var t = text.replaceAll(_ws, ' ');
    if (t.isEmpty) return;
    if (_lastWasSpace && t.startsWith(' ')) t = t.substring(1);
    if (t.isEmpty) return;
    _appendRaw(t, ctx);
    _lastWasSpace = t.endsWith(' ');
  }

  void _appendRaw(String text, _Ctx ctx) {
    if (text.isEmpty) return;
    for (final a in _pendingAnchors) {
      _anchors.add((a, _runLength));
    }
    _pendingAnchors.clear();
    if (_runs.isNotEmpty && _runs.last.style == ctx.style && _runs.last.href == ctx.href) {
      final last = _runs.removeLast();
      _runs.add(InlineRun(last.text + text, style: ctx.style, href: ctx.href));
    } else {
      _runs.add(InlineRun(text, style: ctx.style, href: ctx.href));
    }
    _runLength += text.length;
  }

  void _flush(_Ctx ctx) {
    if (_runs.isEmpty) return;
    // Supprime les espaces de fin.
    final last = _runs.removeLast();
    final trimmed = ctx.preformatted ? last.text.trimRight() : last.text.replaceFirst(RegExp(r'[ \n]+$'), '');
    if (trimmed.isNotEmpty) _runs.add(InlineRun(trimmed, style: last.style, href: last.href));
    final hasText = _runs.any((r) => r.text.trim().isNotEmpty);
    if (hasText) {
      _blocks.add(TextBlock(List.of(_runs), kind: ctx.kind, level: ctx.level, anchors: List.of(_anchors)));
    } else if (_anchors.isNotEmpty) {
      _pendingAnchors.addAll(_anchors.map((a) => a.$1));
    }
    _runs.clear();
    _anchors.clear();
    _runLength = 0;
    _lastWasSpace = true;
  }
}

class _Ctx {
  const _Ctx({this.style = 0, this.href, this.kind = BlockKind.paragraph, this.level = 0, this.preformatted = false});

  final int style;
  final String? href;
  final BlockKind kind;
  final int level;
  final bool preformatted;

  _Ctx copy({int? style, String? href, BlockKind? kind, int? level, bool? preformatted}) => _Ctx(
        style: style ?? this.style,
        href: href ?? this.href,
        kind: kind ?? this.kind,
        level: level ?? this.level,
        preformatted: preformatted ?? this.preformatted,
      );

  _Ctx withInline(String tag, String? css, String? link) {
    var s = style;
    switch (tag) {
      case 'b' || 'strong':
        s |= InlineStyle.bold;
      case 'i' || 'em' || 'cite' || 'dfn' || 'var':
        s |= InlineStyle.italic;
      case 'u' || 'ins':
        s |= InlineStyle.underline;
      case 's' || 'strike' || 'del':
        s |= InlineStyle.strike;
      case 'sup':
        s |= InlineStyle.superscript;
      case 'sub':
        s |= InlineStyle.subscript;
      case 'code' || 'kbd' || 'samp' || 'tt':
        s |= InlineStyle.code;
      case 'small':
        s |= InlineStyle.small;
    }
    if (css != null) {
      if (RegExp(r'font-weight\s*:\s*(bold|[6-9]00)').hasMatch(css)) s |= InlineStyle.bold;
      if (RegExp(r'font-style\s*:\s*italic').hasMatch(css)) s |= InlineStyle.italic;
    }
    return copy(style: s, href: tag == 'a' && link != null ? link : href);
  }

  _Ctx withBlock(String tag, dom.Element e) {
    final css = e.attributes['style'] ?? '';
    final cls = e.className.toLowerCase();
    if (tag.length == 2 && tag.startsWith('h') && int.tryParse(tag.substring(1)) != null) {
      return copy(kind: BlockKind.heading, level: int.parse(tag.substring(1)));
    }
    switch (tag) {
      case 'blockquote':
        return copy(kind: BlockKind.quote);
      case 'pre':
        return copy(kind: BlockKind.preformatted, preformatted: true);
      case 'li':
        return copy(kind: BlockKind.listItem, level: level + 1);
      case 'center':
        return copy(kind: BlockKind.centered);
      case 'figcaption' || 'caption':
        return copy(kind: BlockKind.centered, style: style | InlineStyle.small);
    }
    if (css.contains(RegExp(r'text-align\s*:\s*center')) || cls.contains('center')) {
      return copy(kind: BlockKind.centered);
    }
    if (kind == BlockKind.heading || kind == BlockKind.quote || kind == BlockKind.centered) return this;
    return copy(kind: BlockKind.paragraph);
  }
}
