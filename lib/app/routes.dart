import 'package:material_ui/material_ui.dart';

import '../core/design/tokens.dart';
import '../data/models/book.dart';
import '../features/book/book_detail_screen.dart';
import '../features/reader/reader_screen.dart';

abstract final class Routes {
  static Future<void> bookDetail(BuildContext context, Book book, {String? heroTag}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookDetailScreen(bookId: book.id!, initial: book, heroTag: heroTag),
      ));

  /// Ouverture du livre : zoom + fondu, comme un livre qu'on approche.
  static Future<void> reader(BuildContext context, Book book) {
    final animate = MotionScope.enabledOf(context);
    return Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: animate ? const Duration(milliseconds: 420) : Duration.zero,
      reverseTransitionDuration: animate ? const Duration(milliseconds: 280) : Duration.zero,
      pageBuilder: (_, _, _) => ReaderScreen(bookId: book.id!),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Motion.emphasized);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curved), child: child),
        );
      },
    ));
  }
}
