import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/errors.dart';
import '../../../data/settings/app_settings.dart';
import '../../../formats/document/flow_document.dart';

/// Phrase à prononcer, avec sa position dans le chapitre.
class _Utterance {
  const _Utterance(this.start, this.text, this.blockIndex);
  final int start;
  final String text;
  final int blockIndex;
}

/// Synthèse vocale basée sur les moteurs TTS du système.
///
/// Lit phrase par phrase à partir d'une position ; expose la plage en cours
/// ([sentence], [word]) pour le suivi visuel et passe au chapitre suivant.
class TtsController extends ChangeNotifier {
  TtsController({required this.settings, required this.loadChapter, required this.chapterCount, required this.language});

  final AppSettings settings;
  final Future<FlowChapter> Function(int index) loadChapter;
  final int chapterCount;
  final String language;

  final _tts = FlutterTts();
  bool _initialized = false;
  bool available = true;
  bool playing = false;
  bool active = false;

  int chapter = 0;
  List<_Utterance> _queue = const [];
  int _index = 0;
  int _generation = 0;

  /// Plage (chapitre) de la phrase en cours, et du mot en cours si le moteur le fournit.
  (int, int)? sentence;
  (int, int)? word;

  List<Map<String, String>> voices = const [];

  Future<bool> _init() async {
    if (_initialized) return available;
    _initialized = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      if (language.isNotEmpty) await _tts.setLanguage(language);
      final raw = await _tts.getVoices;
      if (raw is List) {
        voices = [
          for (final v in raw)
            if (v is Map) {for (final e in v.entries) e.key.toString(): e.value.toString()},
        ]..sort((a, b) => (a['locale'] ?? '').compareTo(b['locale'] ?? ''));
      }
      _tts.setProgressHandler((text, start, end, w) {
        final u = _current;
        if (u == null) return;
        word = (u.start + start, u.start + end);
        notifyListeners();
      });
      await _applySettings();
      return true;
    } catch (e, st) {
      AppError.report(e, st, context: 'tts');
      available = false;
      return false;
    }
  }

  Future<void> _applySettings() async {
    await _tts.setSpeechRate(settings.ttsRate);
    await _tts.setPitch(settings.ttsPitch);
    final voice = settings.ttsVoice;
    if (voice != null && voice.contains('|')) {
      final [name, locale] = voice.split('|');
      await _tts.setVoice({'name': name, 'locale': locale});
    }
  }

  Future<void> updateSettings({double? rate, double? pitch, Map<String, String>? voice}) async {
    await settings.setTts(rate: rate, pitch: pitch, voice: voice == null ? null : '${voice['name']}|${voice['locale']}');
    if (!_initialized) return;
    await _applySettings();
    if (playing) await _restartCurrent();
  }

  _Utterance? get _current => _index < _queue.length ? _queue[_index] : null;

  static final _sentenceEnd = RegExp(r'(?<=[.!?…»"])\s+(?=[A-ZÀ-Ý«"—–-])|(?<=[.!?…])\s+');

  static List<_Utterance> _split(FlowChapter c, int fromOffset) {
    final out = <_Utterance>[];
    for (var bi = c.blockIndexAt(fromOffset); bi < c.blocks.length; bi++) {
      final b = c.blocks[bi];
      if (b is! TextBlock) continue;
      final text = b.plainText;
      var pos = 0;
      for (final m in _sentenceEnd.allMatches(text)) {
        _add(out, b.start + pos, text.substring(pos, m.start), bi, fromOffset);
        pos = m.end;
      }
      _add(out, b.start + pos, text.substring(pos), bi, fromOffset);
    }
    return out;
  }

  static void _add(List<_Utterance> out, int start, String text, int block, int from) {
    if (start + text.length <= from) return;
    // Phrase à cheval sur la position de départ : on commence exactement à
    // cette position (haut de page ou mot sélectionné), sans revenir en arrière.
    if (start < from) {
      text = text.substring(from - start);
      start = from;
    }
    if (text.trim().isEmpty) return;
    out.add(_Utterance(start, text, block));
  }

  /// Démarre la lecture à partir d'une position du chapitre.
  Future<void> start(int chapterIndex, int offset) async {
    if (!await _init()) {
      AppError.toast('Synthèse vocale indisponible sur cet appareil');
      return;
    }
    final c = await loadChapter(chapterIndex);
    chapter = chapterIndex;
    _queue = _split(c, offset);
    _index = 0;
    active = true;
    await _play();
  }

  Future<void> _play() async {
    final gen = ++_generation;
    playing = true;
    notifyListeners();
    while (gen == _generation) {
      final u = _current;
      if (u == null) {
        if (chapter + 1 >= chapterCount) break;
        final c = await loadChapter(++chapter);
        if (gen != _generation) return;
        _queue = _split(c, 0);
        _index = 0;
        continue;
      }
      sentence = (u.start, u.start + u.text.length);
      word = null;
      notifyListeners();
      try {
        await _tts.speak(u.text);
      } catch (e, st) {
        AppError.report(e, st, context: 'tts.speak');
        break;
      }
      if (gen != _generation) return;
      _index++;
    }
    if (gen == _generation) {
      playing = false;
      notifyListeners();
    }
  }

  Future<void> _restartCurrent() async {
    _generation++;
    await _tts.stop();
    await _play();
  }

  Future<void> pause() async {
    _generation++;
    playing = false;
    await _tts.stop();
    notifyListeners();
  }

  Future<void> resume() => _play();

  /// Paragraphe suivant (+1) ou précédent (-1).
  Future<void> skipParagraph(int delta) async {
    if (_queue.isEmpty) return;
    final currentBlock = _current?.blockIndex ?? _queue.last.blockIndex;
    var i = _index;
    if (delta > 0) {
      while (i < _queue.length && _queue[i].blockIndex == currentBlock) {
        i++;
      }
    } else {
      while (i > 0 && _queue[i].blockIndex == currentBlock) {
        i--;
      }
      final target = _queue[i].blockIndex;
      while (i > 0 && _queue[i - 1].blockIndex == target) {
        i--;
      }
    }
    _index = i.clamp(0, _queue.length);
    await _restartCurrent();
  }

  Future<void> stop() async {
    _generation++;
    playing = false;
    active = false;
    sentence = null;
    word = null;
    try {
      await _tts.stop();
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _tts.stop().catchError((_) => null);
    super.dispose();
  }
}
