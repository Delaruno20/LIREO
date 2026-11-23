import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/data/db/app_database.dart';
import 'package:lireo/data/models/book.dart';
import 'package:lireo/data/models/library_models.dart';
import 'package:lireo/data/repositories/annotation_repository.dart';
import 'package:lireo/data/repositories/library_repository.dart';
import 'package:lireo/data/repositories/stats_repository.dart';
import 'package:lireo/features/library/library_controller.dart';
import 'package:lireo/features/reader/model/reader_prefs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Book _book(String title, {String author = '', List<String> cats = const [], String? hash}) => Book(
      path: '/tmp/$title',
      fileName: '$title.epub',
      format: 'epub',
      title: title,
      author: author,
      categories: cats,
      fileHash: hash ?? title,
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    repo = LibraryRepository(db.db);
  });
  tearDown(() => db.close());

  test('insertion, recherche, filtres et tri', () async {
    await repo.insertBook(_book('Dune', author: 'Frank Herbert', cats: ['SF']));
    await repo.insertBook(_book('Fondation', author: 'Isaac Asimov', cats: ['SF']));
    await repo.insertBook(_book('Les Fleurs du mal', author: 'Baudelaire', cats: ['Poésie']));
    expect(await repo.count(), 3);
    expect((await repo.books(const BookQuery(search: 'asimov'))).single.title, 'Fondation');
    expect((await repo.books(const BookQuery(category: 'SF'))).length, 2);
    expect((await repo.books(const BookQuery(sort: BookSort.title))).first.title, 'Dune');
    expect(await repo.categories(), ['SF', 'Poésie']);
  });

  test('progression : statut en cours puis terminé', () async {
    final b = await repo.insertBook(_book('Dune'));
    await repo.saveProgress(b.id!, const BookLocation(chapter: 2, offset: 40), 0.4);
    var reading = await repo.books(const BookQuery(status: 'reading'));
    expect(reading.single.locator, const BookLocation(chapter: 2, offset: 40));
    await repo.saveProgress(b.id!, const BookLocation(chapter: 9), 1.0);
    reading = await repo.books(const BookQuery(status: 'reading'));
    expect(reading, isEmpty);
    expect((await repo.books(const BookQuery(status: 'finished'))).single.isFinished, isTrue);
  });

  test('empreinte unique : pas de doublon', () async {
    await repo.insertBook(_book('A', hash: 'h1'));
    expect(() => repo.insertBook(_book('B', hash: 'h1')), throwsA(anything));
    expect((await repo.bookByHash('h1'))!.title, 'A');
  });

  test('collections et collections privées', () async {
    final a = await repo.insertBook(_book('A'));
    final b = await repo.insertBook(_book('B'));
    final pub = await repo.createCollection('Public');
    final priv = await repo.createCollection('Secret', isPrivate: true);
    await repo.addToCollection(pub.id!, [a.id!, b.id!]);
    await repo.addToCollection(priv.id!, [b.id!]);
    expect((await repo.booksInCollection(pub.id!)).length, 2);
    expect(await repo.privateBookIds(), {b.id});
    expect((await repo.collections(includePrivate: false)).map((c) => c.name), ['Public']);
    await repo.deleteBooks([b.id!]);
    expect((await repo.collections()).firstWhere((c) => c.name == 'Public').bookCount, 1);
  });

  test('annotations et export Markdown', () async {
    final b = await repo.insertBook(_book('Dune'));
    final ann = AnnotationRepository(db.db);
    await ann.add(Annotation(
      bookId: b.id!,
      kind: AnnotationKind.note,
      start: const BookLocation(chapter: 0, offset: 3),
      end: const BookLocation(chapter: 0, offset: 10),
      text: 'La peur tue l\'esprit',
      note: 'Litanie',
      createdAt: DateTime.now(),
      chapterTitle: 'Livre I',
    ));
    final list = await ann.forBook(b.id!);
    expect(list.single.note, 'Litanie');
    final md = AnnotationRepository.toMarkdown('Dune', 'Herbert', list);
    expect(md, contains('## Livre I'));
    expect(md, contains("> La peur tue l'esprit"));
  });

  test('statistiques : cumuls, série, sessions trop courtes ignorées', () async {
    final b = await repo.insertBook(_book('Dune'));
    final stats = StatsRepository(db.db);
    final now = DateTime(2026, 11, 19, 20);
    Future<void> session(DateTime d, int minutes, int pages) => stats.recordSession(ReadingSession(
          bookId: b.id!,
          startedAt: d,
          durationMs: minutes * 60000,
          pagesRead: pages,
          startProgress: 0,
          endProgress: 0.1,
        ));
    await session(now, 30, 20);
    await session(now.subtract(const Duration(days: 1)), 20, 10);
    await session(now.subtract(const Duration(days: 2)), 10, 5);
    await session(now.subtract(const Duration(days: 5)), 15, 5);
    await stats.recordSession(ReadingSession(bookId: b.id!, startedAt: now, durationMs: 3000, pagesRead: 1, startProgress: 0, endProgress: 0));
    final s = await stats.summary(now: now);
    expect(s.todayMs, 30 * 60000);
    expect(s.currentStreak, 3);
    expect(s.bestStreak, 3);
    expect(s.pagesRead, 40);
    expect(s.last7Days.last.durationMs, 30 * 60000);
    expect((await repo.book(b.id!))!.totalReadingMs, 75 * 60000);
  });

  test('recommandations basées sur l\'auteur et les catégories lus', () {
    final read = _book('Dune', author: 'Frank Herbert', cats: ['SF']).copyWith(id: 1, lastOpenedAt: DateTime.now());
    final sameAuthor = _book('Le Messie de Dune', author: 'Frank Herbert').copyWith(id: 2);
    final sameCat = _book('Fondation', cats: ['SF']).copyWith(id: 3);
    final other = _book('Recettes', cats: ['Cuisine']).copyWith(id: 4);
    final (list, fromHistory) = HomeController.recommend([read, other, sameCat, sameAuthor]);
    expect(fromHistory, isTrue);
    expect(list.take(2).map((b) => b.title), ['Le Messie de Dune', 'Fondation']);
    expect(list.contains(read), isFalse);
  });

  test('réglages de lecture : sérialisation aller-retour', () {
    const prefs = ReaderPrefs(fontFamily: 'Lora', fontSize: 22, animation: PageAnimation.fade, leftTap: ReaderAction.nextPage);
    final back = ReaderPrefs.decode(prefs.encode());
    expect(back, prefs);
    expect(ReaderPrefs.decode('{corrompu'), const ReaderPrefs());
  });
}
