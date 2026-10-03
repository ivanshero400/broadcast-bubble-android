import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app.dart';

const _nativeChannel = MethodChannel('com.atherstudio.broadcast_bubble/native');

class Idea {
  const Idea({required this.id, required this.title, required this.body});

  final String id;
  final String title;
  final String body;

  Idea copyWith({String? title, String? body}) =>
      Idea(id: id, title: title ?? this.title, body: body ?? this.body);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'body': body};

  factory Idea.fromJson(Object? value) {
    final json = Map<String, dynamic>.from(value! as Map);
    return Idea(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }
}

class AppModel extends ChangeNotifier {
  AppModel._({
    required this._ideas,
    required this.selectedId,
    required this.fontSize,
    required this.bubbleActive,
  });

  List<Idea> _ideas;
  String? selectedId;
  double fontSize;
  bool bubbleActive;
  Future<void> _saveQueue = Future<void>.value();

  List<Idea> get ideas => List.unmodifiable(_ideas);
  bool get hasIdeas => _ideas.isNotEmpty;

  int get selectedIndex {
    if (_ideas.isEmpty) return -1;
    final index = _ideas.indexWhere((idea) => idea.id == selectedId);
    return index < 0 ? 0 : index;
  }

  Idea? get selectedIdea => selectedIndex < 0 ? null : _ideas[selectedIndex];

  static Future<AppModel> load() async {
    final state = await NativeBridge.loadState();
    return _fromState(state);
  }

  static AppModel _fromState(Map<String, dynamic> state) {
    var ideas = <Idea>[];
    try {
      final decoded =
          jsonDecode(state['ideasJson'] as String? ?? '[]') as List<dynamic>;
      ideas = decoded.map(Idea.fromJson).toList();
    } on Object {
      ideas = [];
    }
    final savedFont = (state['fontSize'] as num?)?.toDouble() ?? 30;
    final savedId = state['selectedId'] as String?;
    return AppModel._(
      ideas: ideas,
      selectedId: ideas.any((idea) => idea.id == savedId)
          ? savedId
          : ideas.isEmpty
          ? null
          : ideas.first.id,
      fontSize: savedFont.clamp(22, 48).toDouble(),
      bubbleActive: state['bubbleActive'] as bool? ?? false,
    );
  }

  Future<void> reload() async {
    await _saveQueue.catchError((Object _) {});
    final state = await NativeBridge.loadState();
    final latest = _fromState(state);
    _ideas = latest._ideas;
    selectedId = latest.selectedId;
    fontSize = latest.fontSize;
    bubbleActive = latest.bubbleActive;
    notifyListeners();
  }

  void upsert(Idea idea) {
    final index = _ideas.indexWhere((item) => item.id == idea.id);
    if (index == -1) {
      _ideas = [..._ideas, idea];
    } else {
      _ideas = [..._ideas]..[index] = idea;
    }
    notifyListeners();
    unawaited(persist());
  }

  void remove(String id) {
    _ideas = _ideas.where((idea) => idea.id != id).toList();
    if (selectedId == id) {
      selectedId = _ideas.isEmpty ? null : _ideas.first.id;
    }
    notifyListeners();
    unawaited(persist());
  }

  void move(String id, int offset) {
    final from = _ideas.indexWhere((idea) => idea.id == id);
    final to = from + offset;
    if (from < 0 || to < 0 || to >= _ideas.length) return;
    final next = [..._ideas];
    final item = next.removeAt(from);
    next.insert(to, item);
    _ideas = next;
    notifyListeners();
    unawaited(persist());
  }

  void select(String? id) {
    if (id != null && !_ideas.any((idea) => idea.id == id)) return;
    selectedId = id;
    notifyListeners();
    unawaited(persist());
  }

  void step(int offset) {
    if (_ideas.isEmpty) return;
    final next = (selectedIndex + offset).clamp(0, _ideas.length - 1).toInt();
    select(_ideas[next].id);
  }

  void adjustFont(double offset) {
    fontSize = (fontSize + offset).clamp(22, 48).toDouble();
    notifyListeners();
    unawaited(persist());
  }

  Future<void> persist() {
    final snapshot = <String, Object?>{
      'ideasJson': jsonEncode(_ideas.map((idea) => idea.toJson()).toList()),
      'selectedId': selectedId,
      'fontSize': fontSize.round(),
    };
    final nextSave = _saveQueue
        .catchError((Object _) {})
        .then((_) => NativeBridge.saveState(snapshot));
    _saveQueue = nextSave;
    return nextSave;
  }
}

class NativeBridge {
  static Future<Map<String, dynamic>> loadState() async {
    final result = await _nativeChannel.invokeMapMethod<String, dynamic>(
      'loadState',
    );
    return result ?? <String, dynamic>{};
  }

  static Future<void> saveState(Map<String, Object?> state) async {
    await _nativeChannel.invokeMethod<void>('saveState', state);
  }

  static Future<bool> canDrawOverlays() async =>
      await _nativeChannel.invokeMethod<bool>('canDrawOverlays') ?? false;

  static Future<void> requestOverlayPermission() =>
      _nativeChannel.invokeMethod<void>('requestOverlayPermission');

  static Future<void> startBubble() =>
      _nativeChannel.invokeMethod<void>('startBubble');

  static Future<void> stopBubble() =>
      _nativeChannel.invokeMethod<void>('stopBubble');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final model = await AppModel.load();
  runApp(BroadcastBubbleApp(model: model));
}

class BroadcastBubbleApp extends StatelessWidget {
  const BroadcastBubbleApp({required this.model, super.key});

  final AppModel model;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'فقاعة البث',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3C63D8),
        brightness: Brightness.light,
        surface: const Color(0xFFFFFFFF),
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F6FC),
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF17263F),
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF17263F),
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF17263F),
        ),
        bodyLarge: TextStyle(color: Color(0xFF283750), height: 1.65),
        bodyMedium: TextStyle(color: Color(0xFF53627A), height: 1.55),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F6FC),
        foregroundColor: Color(0xFF17263F),
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    ),
    home: HomePage(model: model),
  );
}
