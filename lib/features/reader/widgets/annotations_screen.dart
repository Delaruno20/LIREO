import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/book.dart';
import '../../../data/models/library_models.dart';
import '../../../data/repositories/annotation_repository.dart';

/// Historique des marque-pages, surlignages et notes d'un livre.
/// Retourne (pop) une [BookLocation] quand l'utilisateur choisit un élément.
class AnnotationsScreen extends StatefulWidget {
  const AnnotationsScreen({super.key, required this.book, this.fromReader = false});

  final Book book;
  final bool fromReader;

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  List<Annotation>? _items;
  AnnotationKind? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await context.read<AnnotationRepository>().forBook(widget.book.id!);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _export() async {
    final items = _items ?? const [];
    final md = AnnotationRepository.toMarkdown(widget.book.title, widget.book.author, items);
    await AppError.guard(() => SharePlus.instance.share(ShareParams(text: md, subject: 'Annotations — ${widget.book.title}')));
  }

  Future<void> _editNote(Annotation a) async {
    final controller = TextEditingController(text: a.note);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(controller: controller, autofocus: true, maxLines: 6, minLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (note == null || !mounted) return;
    await context.read<AnnotationRepository>().update(a.copyWith(note: note, kind: a.kind == AnnotationKind.bookmark ? null : (note.isEmpty ? AnnotationKind.highlight : AnnotationKind.note)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final items = (_items ?? const <Annotation>[]).where((a) => _filter == null || a.kind == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotations'),
        actions: [
          IconButton(tooltip: 'Exporter (Markdown)', icon: const Icon(Icons.ios_share_rounded), onPressed: _items == null || _items!.isEmpty ? null : _export),
        ],
      ),
      body: Column(
        children: [
          FilterChipsRow(
            labels: const ['Tout', 'Surlignages', 'Notes', 'Marque-pages'],
            selected: switch (_filter) {
              null => 0,
              AnnotationKind.highlight => 1,
              AnnotationKind.note => 2,
              AnnotationKind.bookmark => 3,
            },
            onSelected: (i) => setState(() => _filter = [null, AnnotationKind.highlight, AnnotationKind.note, AnnotationKind.bookmark][i]),
          ),
          const SizedBox(height: Space.sm),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const EmptyState(
                        icon: Icons.format_quote_rounded,
                        title: 'Rien pour l\'instant',
                        message: 'Appui long sur un mot pendant la lecture pour surligner, annoter ou copier un passage.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: Space.xxl),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(indent: Space.gutter, endIndent: Space.gutter),
                        itemBuilder: (context, i) {
                          final a = items[i];
                          return Dismissible(
                            key: ValueKey(a.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: Space.xl),
                              color: Theme.of(context).colorScheme.error,
                              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                            ),
                            onDismissed: (_) async {
                              await context.read<AnnotationRepository>().delete(a);
                              setState(() => _items!.remove(a));
                            },
                            child: InkWell(
                              onTap: widget.fromReader ? () => Navigator.pop(context, a.start) : null,
                              onLongPress: () => _editNote(a),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.md),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 46,
                                      margin: const EdgeInsets.only(right: Space.md, top: 2),
                                      decoration: BoxDecoration(
                                        color: a.kind == AnnotationKind.bookmark ? p.primary : Color(a.color),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                switch (a.kind) {
                                                  AnnotationKind.bookmark => Icons.bookmark_rounded,
                                                  AnnotationKind.highlight => Icons.border_color_outlined,
                                                  AnnotationKind.note => Icons.sticky_note_2_outlined,
                                                },
                                                size: 14,
                                                color: p.textMuted,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  [if (a.chapterTitle.isNotEmpty) a.chapterTitle, '${(a.progress * 100).round()} %', formatDate(a.createdAt)].join(' · '),
                                                  style: t.bodySmall,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (a.text.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(a.text, style: t.bodyMedium?.copyWith(fontFamily: Fonts.display, height: 1.45), maxLines: 6, overflow: TextOverflow.ellipsis),
                                          ],
                                          if (a.note.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.all(Space.sm),
                                              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: const BorderRadius.all(Radii.sm)),
                                              child: Text(a.note, style: t.bodyMedium),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
