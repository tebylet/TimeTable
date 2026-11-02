import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/app_user.dart';
import '../services/sync_service.dart';
import '../services/update_installer.dart';
import '../services/update_channel.dart';
import '../theme.dart';
import 'group_select_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ScheduleController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin(ScheduleController c) async {
    final ok =
        await c.loginStaff(_usernameController.text, _passwordController.text);
    if (ok) {
      _usernameController.clear();
      _passwordController.clear();
      if (c.hasStaffSchedule && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _buildPage(context),
      );

  Widget _buildPage(BuildContext context) {
    final c = widget.controller;
    final currentGroupName = c.data.groups
        .where((g) => g.id == c.selectedGroupId)
        .map((g) => g.name)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(Strings.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (!c.hasStaffSchedule) ...[
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppEyebrow(text: Strings.currentGroup),
                  const SizedBox(height: 6),
                  Text(
                    currentGroupName ?? '—',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GroupSelectScreen(
                              controller: c, isChangingGroup: true),
                        ),
                      );
                    },
                    child: Text(Strings.changeGroup),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppEyebrow(text: Strings.themeSection),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final variant in AppThemeVariant.values)
                      _ThemeSwatch(
                        variant: variant,
                        selected: c.themeVariant == variant,
                        onTap: () => c.setThemeVariant(variant),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppEyebrow(text: Strings.languageSection),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final locale in AppLocale.values) ...[
                      Expanded(
                        child: _LanguageOption(
                          locale: locale,
                          selected: c.locale == locale,
                          onTap: () => c.setLocale(locale),
                        ),
                      ),
                      if (locale != AppLocale.values.last)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppEyebrow(text: Strings.syncSection),
                const SizedBox(height: 8),
                Text(
                  c.lastSyncAt == null
                      ? Strings.neverSynced
                      : Strings.lastSyncStatus('${c.lastSyncAt}', c.lastSyncOk),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                if (c.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(c.lastError!,
                      style: TextStyle(color: AppColors.amber, fontSize: 12)),
                ],
                if (c.lastErrorIsCertificateMismatch) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Strings.certificateMismatchNotice,
                          style:
                              TextStyle(color: AppColors.amber, fontSize: 12.5),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => c.retrustServerCertificate(),
                            child: Text(Strings.trustServerCertificateAgain),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: c.isSyncing ? null : () => c.sync(force: true),
                    child:
                        Text(c.isSyncing ? Strings.syncing : Strings.syncNow),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppEyebrow(text: Strings.updateSection),
                const SizedBox(height: 8),
                Text(
                  Strings.currentVersion(c.installedVersionName),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                if (c.updateAvailable && c.latestUpdate != null) ...[
                  Text(
                    Strings.newVersionAvailable(c.latestUpdate!.versionName),
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (c.latestUpdate!.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      Strings.updateNotesTitle,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.latestUpdate!.notes,
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (c.installPhase == InstallPhase.ready)
                    Text(Strings.updateReady,
                        style: TextStyle(color: AppColors.textMuted)),
                  if (!c.isInstallingUpdate)
                    TextButton(
                        onPressed: c.remindUpdateLater,
                        child: Text(Strings.remindLater)),
                  if (c.isInstallingUpdate) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                            value: c.installPhase == InstallPhase.downloading
                                ? (c.installPercent != null
                                    ? c.installPercent! / 100
                                    : null)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          c.installPhase == InstallPhase.installing
                              ? Strings.installingUpdate
                              : Strings.downloadingUpdate(
                                  c.installPercent?.round()),
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 12.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: c.isCheckingUpdate
                            ? null
                            : () => _installUpdate(context, c),
                        child: Text(c.updateActionLabel),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ] else if (c.hasCheckedUpdate && c.updateCheckFailed) ...[
                  Text(
                    Strings.updateCheckFailed,
                    style: TextStyle(color: AppColors.amber, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                ] else if (c.hasCheckedUpdate && !c.isCheckingUpdate) ...[
                  Text(
                    Strings.noUpdateAvailable,
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                ],
                if (c.canMoveToGooglePlay ||
                    (c.updateChannel == UpdateChannel.googlePlay &&
                        c.updateCheckFailed))
                  TextButton(
                      onPressed: () async {
                        try {
                          await c.openGooglePlay();
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text(Strings.updateInstallGenericError)));
                          }
                        }
                      },
                      child: Text(Strings.openGooglePlay)),
                if (!c.isInstallingUpdate && c.supportsUpdates)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed:
                          c.isCheckingUpdate ? null : () => c.checkForUpdate(),
                      child: Text(
                        c.isCheckingUpdate
                            ? Strings.checkingForUpdates
                            : Strings.checkForUpdates,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: c.appUser != null
                ? _StaffLoggedInPanel(controller: c)
                : _StaffLoginForm(
                    controller: c,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    onSubmit: () => _submitLogin(c),
                  ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Text(
                  'PARA',
                  style: TextStyle(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  Strings.developerCredit,
                  style: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.8),
                      fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Форма входа для преподавателей/администраторов — логин и пароль
/// создаются в панели администратора сервера, здесь их только вводят.
/// Ошибки (неверный пароль, блокировка после трёх попыток) приходят прямо
/// с сервера уже готовым текстом (см. ScheduleController.loginError) — само
/// приложение не пытается угадывать их заранее.
class _StaffLoginForm extends StatefulWidget {
  final ScheduleController controller;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final VoidCallback onSubmit;

  const _StaffLoginForm({
    required this.controller,
    required this.usernameController,
    required this.passwordController,
    required this.onSubmit,
  });

  @override
  State<_StaffLoginForm> createState() => _StaffLoginFormState();
}

class _StaffLoginFormState extends State<_StaffLoginForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _buildPage(context),
      );

  Widget _buildPage(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppEyebrow(text: Strings.staffLoginSection),
        const SizedBox(height: 12),
        TextField(
          controller: widget.usernameController,
          enabled: !c.isLoggingIn,
          decoration: InputDecoration(hintText: Strings.usernameLabel),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.passwordController,
          enabled: !c.isLoggingIn,
          obscureText: _obscure,
          decoration: InputDecoration(
            hintText: Strings.passwordLabel,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppColors.textMuted,
              ),
              tooltip: _obscure ? Strings.showPassword : Strings.hidePassword,
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!c.isLoggingIn) widget.onSubmit();
          },
        ),
        if (c.loginError != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (c.loginLocked ? AppColors.error : AppColors.amber)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: (c.loginLocked ? AppColors.error : AppColors.amber)
                      .withValues(alpha: 0.4)),
            ),
            child: Text(
              c.loginError!,
              style: TextStyle(
                color: c.loginLocked ? AppColors.error : AppColors.amber,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: c.isLoggingIn ? null : widget.onSubmit,
            child:
                Text(c.isLoggingIn ? Strings.loggingIn : Strings.loginButton),
          ),
        ),
      ],
    );
  }
}

/// Показывается вместо формы входа, когда преподаватель/администратор уже
/// вошёл в приложении — имя, роль и кнопка выхода.
class _StaffLoggedInPanel extends StatelessWidget {
  final ScheduleController controller;

  const _StaffLoggedInPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final user = controller.appUser!;
    final roleLabel = user.role == AppRole.admin
        ? Strings.roleAdmin
        : user.role == AppRole.coordinator
            ? '${Strings.roleCoordinator} · ${Strings.course(user.courseNumber ?? 1)}'
            : Strings.roleTeacher;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppEyebrow(text: Strings.staffLoginSection),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                Strings.loggedInAs(user.displayName),
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => controller.logoutStaff(),
            child: Text(Strings.logoutButton),
          ),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch(
      {required this.variant, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = variant.palette;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? palette.accent : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                    color: palette.accent, shape: BoxShape.circle),
                child: selected
                    ? Icon(Icons.check_rounded,
                        size: 15, color: palette.onAccent)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            variant.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка-переключатель языка интерфейса ("Русский" / "English").
class _LanguageOption extends StatelessWidget {
  final AppLocale locale;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption(
      {required this.locale, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Text(
          locale.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.onAccent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Скачивает APK и сразу показывает системный экран установки — прогресс
/// отображается прямо в панели "Обновление приложения" (см. build() выше,
/// c.isInstallingUpdate/installPhase/installPercent). Здесь только
/// разбирается финальный результат, чтобы один раз показать snackbar, а не
/// на каждой перерисовке экрана.
Future<void> _installUpdate(BuildContext context, ScheduleController c) async {
  final messenger = ScaffoldMessenger.of(context);
  await c.installUpdate();
  if (!context.mounted) return;

  switch (c.installPhase) {
    case InstallPhase.canceled:
      messenger
          .showSnackBar(SnackBar(content: Text(Strings.updateInstallCanceled)));
      break;
    case InstallPhase.error:
      final needsPermission = c.installError == 'permission_not_granted';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            needsPermission
                ? Strings.updateInstallPermissionNeeded
                : Strings.updateInstallGenericError,
          ),
        ),
      );
      break;
    case InstallPhase.ready:
    case InstallPhase.done:
    case InstallPhase.downloading:
    case InstallPhase.installing:
    case null:
      // "done" обычно вообще не успевает отрисоваться — к этому моменту
      // Android уже показывает свой полноэкранный установщик поверх
      // приложения; сообщение не нужно.
      break;
  }
}
