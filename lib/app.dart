import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart';

const _ink = Color(0xFF17263F);
const _muted = Color(0xFF68768D);
const _blue = Color(0xFF3C63D8);
const _line = Color(0xFFE4EAF3);

class HomePage extends StatefulWidget {
  const HomePage({required this.model, super.key});

  final AppModel model;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _overlayAllowed = false;
  bool _bubbleActive = false;
  bool _checkingPermission = true;
  bool _waitingForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bubbleActive = widget.model.bubbleActive;
    unawaited(_refreshPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.model.reload());
      unawaited(_refreshPermission(startIfGranted: _waitingForPermission));
    }
  }

  Future<void> _refreshPermission({bool startIfGranted = false}) async {
    try {
      final allowed = await NativeBridge.canDrawOverlays();
      final saved = await NativeBridge.loadState();
      if (!mounted) return;
      setState(() {
        _overlayAllowed = allowed;
        _bubbleActive = saved['bubbleActive'] as bool? ?? false;
        _checkingPermission = false;
      });
      if (allowed && startIfGranted && _waitingForPermission) {
        _waitingForPermission = false;
        await _startBubble();
      } else if (startIfGranted) {
        _waitingForPermission = false;
      }
    } on Object {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _startBubble() async {
    try {
      await widget.model.persist();
      await NativeBridge.startBubble();
      widget.model.bubbleActive = true;
      if (mounted) {
        setState(() {
          _bubbleActive = true;
          _overlayAllowed = true;
        });
        _message('الفقاعة جاهزة. اسحبها إلى المكان المناسب فوق تطبيق البث.');
      }
    } on Object {
      if (mounted) {
        _message('تعذّر تشغيل الفقاعة. تأكد من منح إذن الظهور فوق التطبيقات.');
      }
    }
  }

  Future<void> _stopBubble() async {
    await NativeBridge.stopBubble();
    widget.model.bubbleActive = false;
    if (mounted) {
      setState(() => _bubbleActive = false);
      _message('تم إيقاف الفقاعة العائمة.');
    }
  }

  Future<void> _enableBubble() async {
    final allowed = await NativeBridge.canDrawOverlays();
    if (!mounted) return;
    if (allowed) {
      await _startBubble();
      return;
    }
    _waitingForPermission = true;
    final openSettings = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.open_in_new_rounded, size: 34, color: _blue),
            const SizedBox(height: 14),
            Text(
              'السماح بالظهور فوق التطبيقات',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'سيفتح Android صفحة إعدادات فقاعة البث. فعّل «السماح بالظهور فوق التطبيقات»، ثم ارجع إلى هنا؛ ستبدأ الفقاعة تلقائيًا.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.7),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('فتح إعدادات Android'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لاحقًا'),
            ),
          ],
        ),
      ),
    );
    if (openSettings == true) {
      try {
        await NativeBridge.requestOverlayPermission();
      } on Object {
        _waitingForPermission = false;
        if (mounted) {
          _message('افتح إعدادات التطبيقات واسمح لفقاعة البث بالظهور فوقها.');
        }
      }
    } else {
      _waitingForPermission = false;
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editIdea([Idea? existing]) async {
    final id = existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    await showDialog<void>(
      context: context,
      builder: (context) => IdeaEditorDialog(
        existing: existing,
        onChanged: (title, body) {
          if (title.trim().isEmpty && body.trim().isEmpty && existing == null) {
            return;
          }
          widget.model.upsert(Idea(id: id, title: title, body: body));
        },
      ),
    );
  }

  Future<void> _openReader(Idea idea) async {
    widget.model.select(idea.id);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ReaderPage(model: widget.model)),
    );
  }

  Future<void> _deleteIdea(Idea idea) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFB44949),
        ),
        title: const Text('حذف الفكرة؟'),
        content: Text(
          'سيُحذف «${idea.title.isEmpty ? 'فكرة بلا عنوان' : idea.title}» من هذا الجهاز.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف الفكرة'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.model.remove(idea.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.model,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              sliver: SliverList.list(
                children: [
                  _BrandHeader(onAdd: () => _editIdea()),
                  const SizedBox(height: 20),
                  _OverlayCard(
                    allowed: _overlayAllowed,
                    active: _bubbleActive,
                    checking: _checkingPermission,
                    onEnable: _enableBubble,
                    onStop: _stopBubble,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'أفكاري',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.model.hasIdeas
                                  ? '${widget.model.ideas.length} أفكار محفوظة على هذا الجهاز'
                                  : 'اكتب نقاطك، وستبقى محفوظة هنا',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _editIdea(),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('إضافة'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  if (!widget.model.hasIdeas)
                    _EmptyIdeas(onAdd: () => _editIdea())
                  else
                    ...widget.model.ideas.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _IdeaCard(
                          idea: entry.value,
                          index: entry.key,
                          onTap: () => _openReader(entry.value),
                          onEdit: () => _editIdea(entry.value),
                          onDelete: () => _deleteIdea(entry.value),
                          onMoveUp: () => widget.model.move(entry.value.id, -1),
                          onMoveDown: () =>
                              widget.model.move(entry.value.id, 1),
                        ),
                      ),
                    ),
                  const SizedBox(height: 7),
                  const _PrivacyFootnote(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF557CF1), Color(0xFF304FB8)],
          ),
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [
            BoxShadow(
              color: Color(0x223C63D8),
              blurRadius: 15,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.chat_bubble_rounded,
          color: Colors.white,
          size: 25,
        ),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'فقاعة البث',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 2),
            const Text(
              'أفكارك قريبة، حتى أثناء البث',
              style: TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'إضافة فكرة',
        onPressed: onAdd,
        icon: const Icon(Icons.note_add_outlined, color: _blue),
      ),
    ],
  );
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({
    required this.allowed,
    required this.active,
    required this.checking,
    required this.onEnable,
    required this.onStop,
  });

  final bool allowed;
  final bool active;
  final bool checking;
  final VoidCallback onEnable;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final activeColor = active ? const Color(0xFF16816A) : _blue;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: active
              ? const [Color(0xFFE9F7F2), Color(0xFFF4FBF8)]
              : const [Color(0xFFEBF0FF), Color(0xFFF7F9FF)],
        ),
        border: Border.all(
          color: active ? const Color(0xFFD2EBE2) : const Color(0xFFDDE5FC),
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  active ? Icons.bubble_chart_rounded : Icons.layers_rounded,
                  color: activeColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'الفقاعة تعمل' : 'اقرأ أفكارك فوق تطبيق البث',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active
                          ? 'حرّكها إلى طرف الشاشة. اضغطها لفتح لوحة القراءة.'
                          : allowed
                          ? 'فعّل الفقاعة لتظهر فوق التطبيقات الأخرى.'
                          : 'يحتاج Android إلى إذن الظهور فوق التطبيقات.',
                      style: const TextStyle(
                        color: _muted,
                        height: 1.55,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: checking
                  ? null
                  : active
                  ? onStop
                  : onEnable,
              icon: checking
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      active
                          ? Icons.stop_circle_outlined
                          : allowed
                          ? Icons.play_arrow_rounded
                          : Icons.tune_rounded,
                      size: 19,
                    ),
              label: Text(
                checking
                    ? 'جارٍ التحقق…'
                    : active
                    ? 'إيقاف الفقاعة'
                    : allowed
                    ? 'تشغيل الفقاعة'
                    : 'منح الإذن وتشغيلها',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: active ? const Color(0xFF16816A) : _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (!allowed && !checking) ...[
            const SizedBox(height: 9),
            const Text(
              'سنشرح لك الخطوة قبل فتح صفحة إعداد Android.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.index,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final Idea idea;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 15, 14),
        decoration: BoxDecoration(
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(19),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080E1C36),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idea.title.trim().isEmpty ? 'فكرة بلا عنوان' : idea.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      idea.body.trim().isEmpty
                          ? 'اضغط لكتابة التفاصيل…'
                          : idea.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: idea.body.trim().isEmpty
                            ? const Color(0xFF9AA5B5)
                            : _muted,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<_IdeaAction>(
              tooltip: 'خيارات الفكرة',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz_rounded, color: _muted),
              onSelected: (action) {
                switch (action) {
                  case _IdeaAction.edit:
                    onEdit();
                  case _IdeaAction.up:
                    onMoveUp();
                  case _IdeaAction.down:
                    onMoveDown();
                  case _IdeaAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _IdeaAction.edit,
                  child: _MenuLine(icon: Icons.edit_outlined, label: 'تعديل'),
                ),
                PopupMenuItem(
                  value: _IdeaAction.up,
                  child: _MenuLine(
                    icon: Icons.arrow_upward_rounded,
                    label: 'نقل إلى الأعلى',
                  ),
                ),
                PopupMenuItem(
                  value: _IdeaAction.down,
                  child: _MenuLine(
                    icon: Icons.arrow_downward_rounded,
                    label: 'نقل إلى الأسفل',
                  ),
                ),
                PopupMenuItem(
                  value: _IdeaAction.delete,
                  child: _MenuLine(
                    icon: Icons.delete_outline_rounded,
                    label: 'حذف',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

enum _IdeaAction { edit, up, down, delete }

class _MenuLine extends StatelessWidget {
  const _MenuLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 11), Text(label)],
  );
}

class _EmptyIdeas extends StatelessWidget {
  const _EmptyIdeas({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.fromLTRB(22, 28, 22, 25),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      children: [
        Container(
          width: 61,
          height: 61,
          decoration: const BoxDecoration(
            color: Color(0xFFF0F3FA),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lightbulb_outline_rounded,
            size: 30,
            color: Color(0xFF8390A4),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'لا توجد أفكار بعد',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'أضف أول فكرة، ثم افتحها للقراءة أو اعرضها في الفقاعة أثناء البث.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, height: 1.65, fontSize: 13),
        ),
        const SizedBox(height: 17),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('اكتب أول فكرة'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PrivacyFootnote extends StatelessWidget {
  const _PrivacyFootnote();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 9),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 15, color: Color(0xFF8793A7)),
        SizedBox(width: 6),
        Text(
          'أفكارك محفوظة محليًا على هذا الجهاز',
          style: TextStyle(color: Color(0xFF8793A7), fontSize: 11.5),
        ),
      ],
    ),
  );
}

class IdeaEditorDialog extends StatefulWidget {
  const IdeaEditorDialog({required this.onChanged, this.existing, super.key});

  final Idea? existing;
  final void Function(String title, String body) onChanged;

  @override
  State<IdeaEditorDialog> createState() => _IdeaEditorDialogState();
}

class _IdeaEditorDialogState extends State<IdeaEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );
    _bodyController = TextEditingController(text: widget.existing?.body ?? '');
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 220), _saveNow);
  }

  void _saveNow() {
    widget.onChanged(_titleController.text, _bodyController.text);
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        _saveTimer?.cancel();
        _saveNow();
      }
    },
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(21, 20, 21, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'فكرة جديدة' : 'تعديل الفكرة',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _saveNow();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _FieldLabel(label: 'العنوان'),
              const SizedBox(height: 7),
              TextField(
                controller: _titleController,
                autofocus: widget.existing == null,
                textInputAction: TextInputAction.next,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                maxLength: 90,
                onChanged: _changed,
                decoration: _inputDecoration('مثال: النقطة الأساسية'),
              ),
              const SizedBox(height: 8),
              const _FieldLabel(label: 'النص'),
              const SizedBox(height: 7),
              TextField(
                controller: _bodyController,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                minLines: 6,
                maxLines: 12,
                onChanged: _changed,
                decoration: _inputDecoration(
                  'اكتب ما تريد تذكّره أو قوله أثناء البث…',
                ),
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    size: 16,
                    color: Color(0xFF42836F),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'يحفظ تلقائيًا على هذا الجهاز',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              FilledButton(
                onPressed: () {
                  _saveNow();
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(47),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('تم'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _ink,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
  );
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Color(0xFF98A4B5), fontSize: 13),
  filled: true,
  fillColor: const Color(0xFFF8FAFD),
  counterStyle: const TextStyle(color: _muted, fontSize: 11),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: _line),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: _line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: _blue, width: 1.5),
  ),
);

class ReaderPage extends StatelessWidget {
  const ReaderPage({required this.model, super.key});

  final AppModel model;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final idea = model.selectedIdea;
      final index = model.selectedIndex;
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'قراءة الفكرة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'تصغير الخط',
              onPressed: () => model.adjustFont(-2),
              icon: const Icon(Icons.text_decrease_rounded),
            ),
            Center(
              child: Text(
                '${model.fontSize.round()}',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ),
            IconButton(
              tooltip: 'تكبير الخط',
              onPressed: () => model.adjustFont(2),
              icon: const Icon(Icons.text_increase_rounded),
            ),
            const SizedBox(width: 5),
          ],
        ),
        body: idea == null
            ? const Center(
                child: Text(
                  'لا توجد أفكار محفوظة. أضف فكرة من الصفحة الرئيسية.',
                ),
              )
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 9, 18, 17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9EEFC),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Text(
                          'الفكرة ${index + 1} من ${model.ideas.length}',
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        idea.title.trim().isEmpty
                            ? 'فكرة بلا عنوان'
                            : idea.title,
                        style: const TextStyle(
                          fontSize: 23,
                          height: 1.45,
                          color: _ink,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 13),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: _line),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              key: PageStorageKey<String>('reader-${idea.id}'),
                              padding: const EdgeInsets.fromLTRB(
                                21,
                                20,
                                21,
                                24,
                              ),
                              child: SelectableText(
                                idea.body.trim().isEmpty
                                    ? 'لا يوجد نص لهذه الفكرة بعد.'
                                    : idea.body,
                                style: TextStyle(
                                  fontSize: model.fontSize,
                                  height: 1.75,
                                  color: const Color(0xFF273853),
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: index > 0
                                  ? () => model.step(-1)
                                  : null,
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 19,
                              ),
                              label: const Text('السابقة'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(49),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: index < model.ideas.length - 1
                                  ? () => model.step(1)
                                  : null,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 19,
                              ),
                              label: const Text('التالية'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(49),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );
}
