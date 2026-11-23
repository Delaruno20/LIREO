import 'package:material_ui/material_ui.dart';

import '../../data/models/book.dart';
import '../design/palette.dart';
import '../design/tokens.dart';
import 'book_cover.dart';
import 'common.dart';

/// Planche d'étagère en bois avec profondeur.
class ShelfPlank extends StatelessWidget {
  const ShelfPlank({super.key});

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    return Column(
      children: [
        Container(
          height: 9,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(p.shelfTop, Colors.black, 0.18)!, p.shelfTop],
            ),
          ),
        ),
        Container(
          height: 10,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(p.shelfFront, Colors.white, 0.12)!, p.shelfFront],
            ),
            boxShadow: [
              BoxShadow(color: p.shadow, blurRadius: 14, offset: const Offset(0, 8)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rangée de livres posés sur une étagère (défilement horizontal).
class ShelfRow extends StatelessWidget {
  const ShelfRow({
    super.key,
    required this.books,
    required this.onOpen,
    this.onLongPress,
    this.coverWidth = 100,
    this.heroPrefix = 'shelf',
    this.showProgress = true,
  });

  final List<Book> books;
  /// Reçoit le livre et le tag Hero de sa couverture.
  final void Function(Book book, String heroTag) onOpen;
  final ValueChanged<Book>? onLongPress;
  final double coverWidth;
  final String heroPrefix;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final height = coverWidth * BookCover.aspect;
    return SizedBox(
      height: height + 24,
      child: Stack(
        children: [
          const Positioned(left: 0, right: 0, bottom: 0, child: ShelfPlank()),
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter + 4),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.lg),
            itemBuilder: (context, i) {
              final b = books[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FadeSlideIn(
                    index: i,
                    child: Pressable(
                      onTap: () => onOpen(b, '$heroPrefix-${b.id}'),
                      onLongPress: onLongPress == null ? null : () => onLongPress!(b),
                      semanticLabel: '${b.title}, ${b.displayAuthor}',
                      child: BookCover(
                        book: b,
                        width: coverWidth,
                        heroTag: '$heroPrefix-${b.id}',
                        showProgress: showProgress,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Livre en grille : couverture + titre + auteur.
class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    required this.width,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.heroPrefix = 'grid',
    this.showText = true,
  });

  final Book book;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// null = pas en mode sélection.
  final bool? selected;
  final String heroPrefix;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: '${book.title}, ${book.displayAuthor}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              BookCover(book: book, width: width, heroTag: '$heroPrefix-${book.id}', showProgress: true),
              if (selected != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedContainer(
                    duration: Motion.scaled(context, Motion.fast),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected! ? p.primary : Colors.black.withValues(alpha: 0.35),
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                    child: selected! ? Icon(Icons.check_rounded, size: 16, color: p.onPrimary) : null,
                  ),
                ),
              if (book.favorite)
                const Positioned(
                  bottom: 12,
                  right: 6,
                  child: Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFF3A0B5), shadows: [Shadow(blurRadius: 6)]),
                ),
            ],
          ),
          if (showText) ...[
            const SizedBox(height: Space.sm),
            SizedBox(
              width: width,
              child: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(height: 1.2)),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: width,
              child: Text(book.displayAuthor, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
            ),
          ],
        ],
      ),
    );
  }
}
