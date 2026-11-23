import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../core/widgets/book_cover.dart';
import '../../data/models/book.dart';
import '../../data/repositories/library_repository.dart';
import '../../services/import_service.dart';

/// Modification manuelle des métadonnées et de la couverture.
class EditBookScreen extends StatefulWidget {
  const EditBookScreen({super.key, required this.book});
  final Book book;

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _EditBookScreenState extends State<EditBookScreen> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _publisher = TextEditingController(text: widget.book.publisher);
  late final _language = TextEditingController(text: widget.book.language);
  late final _categories = TextEditingController(text: widget.book.categories.join(', '));
  late final _description = TextEditingController(text: widget.book.description);
  late Book _book = widget.book;

  Future<void> _changeCover() async {
    final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choisir une couverture');
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final path = await context.read<ImportService>().replaceCover(_book, bytes);
    if (path != null) setState(() => _book = _book.copyWith(coverPath: path));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      AppError.toast('Le titre est obligatoire');
      return;
    }
    await context.read<LibraryRepository>().updateBook(_book.copyWith(
          title: _title.text.trim(),
          author: _author.text.trim(),
          publisher: _publisher.text.trim(),
          language: _language.text.trim(),
          categories: _categories.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          description: _description.text.trim(),
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final c in [_title, _author, _publisher, _language, _categories, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c, {int lines = 1, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(controller: c, maxLines: lines, minLines: 1, decoration: InputDecoration(hintText: hint)),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier'),
        actions: [TextButton(onPressed: _save, child: const Text('Enregistrer')), const SizedBox(width: Space.sm)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          Center(
            child: Column(
              children: [
                BookCover(book: _book, width: 110),
                TextButton.icon(onPressed: _changeCover, icon: const Icon(Icons.image_outlined), label: const Text('Changer la couverture')),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          field('Titre', _title),
          field('Auteur', _author),
          field('Éditeur', _publisher),
          field('Langue', _language, hint: 'fr, en…'),
          field('Catégories', _categories, hint: 'Séparées par des virgules'),
          field('Description', _description, lines: 8),
        ],
      ),
    );
  }
}
