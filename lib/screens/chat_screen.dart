import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/app_message.dart';
import '../models/group.dart';
import '../models/app_user.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';

/// Лента сообщений от преподавателей/администраторов — и старых, и новых
/// (все они приходят вместе с расписанием, см. ScheduleData.messages, и
/// кэшируются на телефоне, так что доступны и без интернета). Показывает
/// сообщения для группы, которую сейчас смотрит пользователь: адресованные
/// именно ей плюс те, что разосланы сразу всем группам.
///
/// Это лента объявлений, а не переписка: писать сюда могут только вошедшие
/// в приложении преподаватели/администраторы (см. ScheduleController.
/// canSendMessages) — студенты только читают.
class ChatScreen extends StatefulWidget {
  final ScheduleController controller;

  const ChatScreen({super.key, required this.controller});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _bodyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int? _targetGroupId; // null = все группы
  bool _sending = false;
  bool _didInitialScroll = false;
  bool _showMineOnly = false;
  final Set<int> _deleting = {};

  Future<void> _deleteMessage(AppMessage message) async {
    if (_deleting.contains(message.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Strings.deleteMessage),
        content: Text(Strings.deleteMessageConfirmation),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(Strings.dialogCancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(Strings.deleteMessage,
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deleting.contains(message.id)) return;
    setState(() => _deleting.add(message.id));
    try {
      await widget.controller.deleteMessage(message);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is ApiException ? error.message : '$error')));
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(message.id));
    }
  }

  @override
  void initState() {
    super.initState();
    // Открыли вкладку "Чат" — считаем все текущие сообщения увиденными,
    // значок непрочитанных на иконке чата (см. ScheduleScreen) пропадёт.
    widget.controller.markMessagesSeen();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _send(ScheduleController controller) async {
    final text = _bodyController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await controller.sendMessage(targetGroupId: _targetGroupId, body: text);
      _bodyController.clear();
      _scrollToBottom(animate: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e is ApiException ? e.message : '$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(title: Text(Strings.chatTitle)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final canSend = controller.canSendMessages;
          final mineOnly = canSend && _showMineOnly;
          final messages =
              mineOnly ? controller.myMessages : controller.visibleMessages;

          if (!_didInitialScroll && messages.isNotEmpty) {
            _didInitialScroll = true;
            _scrollToBottom();
          }

          return Column(
            children: [
              // Переключатель видим только вошедшим преподавателям/админам —
              // студентам показывать нечего, у них нет своих сообщений.
              if (canSend)
                _MineFilterToggle(
                  showMineOnly: _showMineOnly,
                  onChanged: (v) => setState(() => _showMineOnly = v),
                ),
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Text(
                          mineOnly ? Strings.chatEmptyMine : Strings.chatEmpty,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _MessageBubble(
                          message: messages[index],
                          deleting: _deleting.contains(messages[index].id),
                          onDelete: controller.canDeleteMessage(messages[index])
                              ? () => _deleteMessage(messages[index])
                              : null,
                          groupName: _groupNameFor(
                              controller, messages[index].targetGroupId),
                        ),
                      ),
              ),
              if (canSend)
                _ComposeBar(
                  bodyController: _bodyController,
                  sending: _sending,
                  targetGroupId: _targetGroupId,
                  groups: controller.messageTargetGroups,
                  allGroupsLabel:
                      controller.appUser?.role == AppRole.coordinator
                          ? Strings.messageTargetCourse
                          : Strings.messageTargetAllGroups,
                  onTargetChanged: (id) => setState(() => _targetGroupId = id),
                  onSend: () => _send(controller),
                ),
            ],
          );
        },
      ),
    );
  }

  String? _groupNameFor(ScheduleController controller, int? groupId) {
    if (groupId == null) return null;
    for (final g in controller.data.groups) {
      if (g.id == groupId) return g.name;
    }
    return null;
  }
}

/// Переключатель "Все сообщения" / "Отправленные мной" — виден только
/// вошедшим преподавателям/админам (см. ScheduleController.canSendMessages),
/// чтобы автор мог посмотреть список того, что он сам кому отправил (см.
/// ScheduleController.myMessages).
class _MineFilterToggle extends StatelessWidget {
  final bool showMineOnly;
  final ValueChanged<bool> onChanged;

  const _MineFilterToggle(
      {required this.showMineOnly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(Strings.messagesFilterAll)),
            ButtonSegment(value: true, label: Text(Strings.messagesFilterMine)),
          ],
          selected: {showMineOnly},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AppMessage message;
  final String? groupName;
  final bool deleting;
  final VoidCallback? onDelete;

  const _MessageBubble(
      {required this.message,
      required this.groupName,
      this.deleting = false,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt.toLocal();
    final timeLabel =
        '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(
                message.senderName,
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              )),
              if (onDelete != null)
                deleting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        key: ValueKey('delete-message-${message.id}'),
                        tooltip: Strings.deleteMessage,
                        onPressed: onDelete,
                        icon: Icon(Icons.delete_outline_rounded,
                            color: AppColors.textMuted, size: 20)),
            ]),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    groupName ?? Strings.messageSentTagAll,
                    style: TextStyle(
                        color: AppColors.violet,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                Text(timeLabel,
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
              ],
            ),
            const SizedBox(height: 6),
            Text(message.body,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 13.5, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _ComposeBar extends StatelessWidget {
  final TextEditingController bodyController;
  final bool sending;
  final int? targetGroupId;
  final List<Group> groups;
  final String? allGroupsLabel;
  final ValueChanged<int?> onTargetChanged;
  final VoidCallback onSend;

  const _ComposeBar({
    required this.bodyController,
    required this.sending,
    required this.targetGroupId,
    required this.groups,
    this.allGroupsLabel,
    required this.onTargetChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 32,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: targetGroupId,
                  isDense: true,
                  dropdownColor: AppColors.surface,
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                            allGroupsLabel ?? Strings.messageTargetAllGroups)),
                    for (final g in groups)
                      DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: onTargetChanged,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: bodyController,
                    minLines: 1,
                    maxLines: 4,
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: Strings.messageComposeHint,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: sending ? null : onSend,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                  ),
                  icon: sending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.onAccent),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
