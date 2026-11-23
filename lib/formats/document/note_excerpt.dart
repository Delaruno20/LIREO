import 'flow_document.dart';

/// Extrait d'une note (note de bas de page, définition, glossaire) ciblée par
/// un lien interne, pour l'afficher en surimpression sans quitter la page.
///
/// Renvoie null quand l'ancre ressemble plutôt à une destination de
/// navigation (titre de chapitre, renvoi au milieu d'un paragraphe) : le
/// lecteur saute alors à la cible comme avant.
List<List<InlineRun>>? noteExcerpt(FlowChapter chapter, String anchor, {int maxChars = 1500, int maxBlocks = 4}) {
  final offset = chapter.anchors[anchor];
  if (offset == null || chapter.blocks.isEmpty) return null;
  final first = chapter.blockIndexAt(offset);
  final block = chapter.blocks[first];
  // Une note commence son bloc ; une ancre au milieu du texte est un renvoi
  // (ex. lien « retour » d'une note vers l'appel dans le texte).
  if (block is! TextBlock || block.kind == BlockKind.heading || offset - block.start > 3) return null;

  final result = <List<InlineRun>>[block.runs];
  var chars = block.length;
  for (var i = first + 1; i < chapter.blocks.length && result.length < maxBlocks && chars < maxChars; i++) {
    final b = chapter.blocks[i];
    // Arrêt au début de la note suivante, à un titre ou à une image.
    if (b is! TextBlock || b.kind == BlockKind.heading || b.anchors.any((a) => a.$2 <= 3)) break;
    if (chars + b.length > maxChars) break;
    result.add(b.runs);
    chars += b.length;
  }
  return result.any((runs) => runs.any((r) => r.text.trim().isNotEmpty)) ? result : null;
}
