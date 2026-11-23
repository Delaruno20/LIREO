import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/book_cover.dart';
import '../../core/widgets/common.dart';
import '../../data/models/book.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../formats/format_registry.dart';
import '../../services/app_lock.dart';

/// Recherche instantanée (titre, auteur, éditeur, catégorie).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Book> _results = const [];
  bool _searched = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final repo = context.read<LibraryRepository>();
    var results = await repo.books(BookQuery(search: q, sort: BookSort.title, limit: 200));
    if (!mounted) return;
    if (context.read<AppSettings>().hidePrivateCollections && !context.read<AppLock>().privateUnlocked) {
      final hidden = await repo.privateBookIds();
      results = results.where((b) => !hidden.contains(b.id)).toList();
    }
    if (!mounted || _controller.text != q) return;
    setState(() {
      _results = results;
      _searched = true;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Hero(
          tag: 'search-bar',
          child: Material(
            color: Colors.transparent,
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Titre, auteur, catégorie…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
        ),
        actions: const [SizedBox(width: Space.md)],
      ),
      body: !_searched
          ? EmptyState(icon: Icons.manage_search_rounded, title: 'Rechercher', message: 'Les résultats s\'affichent pendant la saisie.')
          : _results.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Aucun résultat', message: 'Essayez un autre mot-clé.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final b = _results[i];
                    return ListTile(
                      leading: BookCover(book: b, width: 40, heroTag: 'search-${b.id}', elevation: 0.5),
                      title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                      subtitle: Text(
                        [b.displayAuthor, FormatRegistry.byId(b.format).label, if (b.categories.isNotEmpty) b.categories.first].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: b.progress > 0 ? Text('${(b.progress * 100).round()} %', style: t.labelMedium?.copyWith(color: p.primary)) : null,
                      onTap: () => Routes.bookDetail(context, b, heroTag: 'search-${b.id}'),
                    );
                  },
                ),
    );
  }
}
