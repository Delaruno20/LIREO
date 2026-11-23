import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../data/models/book.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../formats/adapters/image_book.dart';
import '../../formats/document/flow_document.dart';
import '../../formats/format_registry.dart';
import '../book/book_detail_screen.dart';
import 'images/image_reader_view.dart';
import 'model/reader_prefs.dart';
import 'pdf/pdf_reader_view.dart';
import 'reflow/reflow_reader_view.dart';
import 'session/reading_tracker.dart';
import 'widgets/reader_settings_panel.dart';

/// Point d'entrée du lecteur : charge le livre, résout ses réglages
/// (livre › profil du format › global) et choisit le moteur adapté.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.bookId});
  final int bookId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  Book? _book;
  ReflowableBook? _reflow;
  ImageBook? _images;
  ReaderPrefs? _prefs;
  PrefsScope _scope = PrefsScope.global;
  ReadingTracker? _tracker;
  Object? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open();
  }

  Future<void> _open() async {
    final settings = context.read<AppSettings>();
    final library = context.read<LibraryRepository>();
    final stats = context.read<StatsRepository>();
    try {
      final book = await library.book(widget.bookId);
      if (book == null) throw const UserFacingError('Ce livre n\'existe plus dans la bibliothèque.');
      if (!await File(book.path).exists()) throw const UserFacingError('Le fichier de ce livre est introuvable.');
      final format = FormatRegistry.byId(book.format);

      final profile = settings.profileForFormat(book.format);
      final prefs = book.readerPrefs != null
          ? ReaderPrefs.decode(book.readerPrefs, fallback: settings.readerPrefs)
          : (profile?.prefs ?? settings.readerPrefs);
      _scope = book.readerPrefs != null ? PrefsScope.book : PrefsScope.global;

      switch (format.engine) {
        case EngineKind.reflowable:
          _reflow = await FormatRegistry.openReflowable(book.path, book.format, book.title);
        case EngineKind.images:
          _images = await FormatRegistry.openImages(book.path, book.format);
        case EngineKind.pdf:
          break;
      }
      if (!mounted) return;
      await library.saveProgress(book.id!, book.locator, book.progress);
      if (prefs.keepScreenOn) WakelockPlus.enable().catchError((_) {});
      setState(() {
        _book = book;
        _prefs = prefs;
        _tracker = ReadingTracker(
          bookId: book.id!,
          library: library,
          stats: stats,
          startProgress: book.progress,
          breakReminder: Duration(minutes: settings.breakReminderMinutes),
          onBreakReminder: (d) => AppError.toast('Vous lisez depuis ${d.inMinutes} min. Pensez à reposer vos yeux.'),
        );
      });
    } catch (e, st) {
      AppError.report(e, st, context: 'open book');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _savePrefs(ReaderPrefs prefs, PrefsScope scope) async {
    final book = _book;
    if (book == null) return;
    _prefs = prefs;
    _scope = scope;
    if (prefs.keepScreenOn) {
      WakelockPlus.enable().catchError((_) {});
    } else {
      WakelockPlus.disable().catchError((_) {});
    }
    final library = context.read<LibraryRepository>();
    // Seule la colonne des réglages est écrite : la progression est gérée par le tracker.
    if (scope == PrefsScope.book) {
      _book = book.copyWith(readerPrefs: prefs.encode());
      await library.setReaderPrefs(book.id!, prefs.encode());
    } else {
      await context.read<AppSettings>().setReaderPrefs(prefs);
      if (book.readerPrefs != null) {
        _book = book.copyWith(clearReaderPrefs: true);
        await library.setReaderPrefs(book.id!, null);
      }
    }
  }

  void _openDetails() {
    final book = _book;
    if (book == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: book.id!, initial: book)));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable().catchError((_) {});
    _tracker?.close();
    _reflow?.close();
    _images?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final prefs = _prefs;
    final tracker = _tracker;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined, size: 48),
                const SizedBox(height: Space.lg),
                Text('Impossible d\'ouvrir ce livre', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Space.sm),
                Text(AppError.describe(_error!), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    if (book == null || prefs == null || tracker == null) {
      return Scaffold(
        backgroundColor: (prefs ?? context.read<AppSettings>().readerPrefs).background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return PopScope(
      child: switch (FormatRegistry.byId(book.format).engine) {
        EngineKind.reflowable => ReflowReaderView(
            book: book,
            document: _reflow!,
            prefs: prefs,
            scope: _scope,
            tracker: tracker,
            onPrefsChanged: _savePrefs,
            onOpenDetails: _openDetails,
          ),
        EngineKind.pdf => PdfReaderView(
            book: book,
            prefs: prefs,
            scope: _scope,
            tracker: tracker,
            onPrefsChanged: _savePrefs,
            onOpenDetails: _openDetails,
          ),
        EngineKind.images => ImageReaderView(
            book: book,
            images: _images!,
            prefs: prefs,
            tracker: tracker,
            onPrefsChanged: _savePrefs,
          ),
      },
    );
  }
}
