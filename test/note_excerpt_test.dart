import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/formats/document/flow_document.dart';
import 'package:lireo/formats/document/html_converter.dart';
import 'package:lireo/formats/document/note_excerpt.dart';

FlowChapter chapter(String html) => FlowChapter(index: 0, title: '', blocks: HtmlFlowConverter.parse(html));

String? text(FlowChapter c, String anchor) =>
    noteExcerpt(c, anchor)?.map((runs) => runs.map((r) => r.text).join()).join(' | ');

void main() {
  test('note de bas de page : paragraphe ciblé seulement', () {
    final c = chapter('''<h2>Notes</h2>
      <p id="n1"><a href="ch1.xhtml#r1">1.</a> Première définition.</p>
      <p id="n2"><a href="ch1.xhtml#r2">2.</a> Seconde.</p>''');
    expect(text(c, 'n1'), '1. Première définition.');
    expect(text(c, 'n2'), '2. Seconde.');
  });

  test('aside EPUB3 sur plusieurs paragraphes', () {
    final c = chapter('''<p>Texte <a id="r1" href="#fn1">1</a> courant.</p>
      <aside epub:type="footnote" id="fn1"><p>Ligne A.</p><p>Ligne B.</p></aside>
      <aside id="fn2"><p>Autre note.</p></aside>''');
    expect(text(c, 'fn1'), 'Ligne A. | Ligne B.');
  });

  test('glossaire dt/dd', () {
    final c = chapter('<dl><dt id="t1">Marée</dt><dd>Mouvement de la mer.</dd><dt id="t2">Étale</dt><dd>Pause.</dd></dl>');
    expect(text(c, 't1'), 'Marée | Mouvement de la mer.');
  });

  test('titre ou renvoi en milieu de texte : navigation classique', () {
    final c = chapter('<h1 id="ch">Chapitre</h1><p>Un long texte avec <a id="r1">appel</a>.</p>');
    expect(noteExcerpt(c, 'ch'), isNull);
    expect(noteExcerpt(c, 'r1'), isNull);
    expect(noteExcerpt(c, 'absent'), isNull);
  });
}
