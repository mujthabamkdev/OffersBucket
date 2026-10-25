import 'package:flutter/material.dart';

import 'models/notification_capture.dart';
import 'services/notification_capture_controller.dart';
import 'widgets/app_brand.dart';
import 'widgets/app_layout.dart';

class NotificationCapturePage extends StatefulWidget {
  const NotificationCapturePage({
    super.key,
    required this.controller,
    required this.onReview,
    this.showInbox = false,
  });

  final NotificationCaptureController controller;
  final Future<bool> Function(CapturedNotification) onReview;
  final bool showInbox;

  @override
  State<NotificationCapturePage> createState() =>
      _NotificationCapturePageState();
}

class _NotificationCapturePageState extends State<NotificationCapturePage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  late bool _showInbox = widget.showInbox;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.controller.state.isSupported) {
      widget.controller.refresh(reloadApps: false);
    }
  }

  Future<void> _openAccessSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow notification access?'),
        content: const Text(
          'Android grants access to notifications from all apps. OffersBucket '
          'reads and stores message text only from apps you select, and only '
          'while capture is enabled. Email previews may include personal '
          'messages. Captures are stored locally and are not uploaded.\n\n'
          'You can pause capture, remove allowed apps, delete captures, or '
          'revoke access in Android settings at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Android settings'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final opened = await widget.controller.openAccessSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Android notification settings.'),
          ),
        );
      }
    }
  }

  Future<void> _clearCaptures() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete captured messages?'),
        content: const Text('This does not delete offers you already saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete captures'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.controller.clearNotifications();
    }
  }

  Future<void> _review(CapturedNotification notification) async {
    final saved = await widget.onReview(notification);
    if (!saved || !mounted) return;
    final removed = await widget.controller.deleteNotification(notification.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? 'Offer saved'
              : 'Offer saved. Could not remove the capture.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final state = controller.state;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Notification capture',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh capture and installed apps',
                onPressed: controller.isLoading
                    ? null
                    : () => controller.refresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: AppBrandMark(size: 32),
              ),
            ],
          ),
          body: AppBackground(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppLayout.maxPageWidth,
                  ),
                  child: state.isSupported
                      ? LayoutBuilder(
                          builder: (context, constraints) => _supportedContent(
                            state,
                            controller,
                            constraints.maxWidth,
                          ),
                        )
                      : const AppPageScroll(
                          maxWidth: AppLayout.maxFormWidth,
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Automatic notification capture is available on '
                                'Android only. iOS does not allow apps to read '
                                'notifications or list all installed apps.\n\n'
                                'Use Add offer to paste notification or email text. '
                                'Email account sign-in is not inbox access.',
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _supportedContent(
    NotificationCaptureState state,
    NotificationCaptureController controller,
    double width,
  ) {
    final gutter = AppLayout.gutter(width);
    final contentWidth = width - gutter * 2;
    final compactLabels =
        contentWidth < 300 || MediaQuery.textScalerOf(context).scale(14) > 18;
    final showIcons = contentWidth >= 360 && !compactLabels;
    return CustomScrollView(
      key: ValueKey(_showInbox),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.isLoading) const LinearProgressIndicator(),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _captureControls(state, controller),
                const SizedBox(height: 20),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(compactLabels ? 'Apps' : 'Allowed apps'),
                      tooltip: 'Allowed apps',
                      icon: showIcons ? const Icon(Icons.apps_rounded) : null,
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(compactLabels ? 'Inbox' : 'Messages'),
                      tooltip: 'Captured messages',
                      icon: showIcons ? const Icon(Icons.inbox_outlined) : null,
                    ),
                  ],
                  selected: {_showInbox},
                  onSelectionChanged: (selection) =>
                      setState(() => _showInbox = selection.single),
                ),
              ],
            ),
          ),
        ),
        for (final sliver
            in _showInbox
                ? _inbox(state, controller)
                : _appList(state, controller))
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            sliver: sliver,
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  Widget _captureControls(
    NotificationCaptureState state,
    NotificationCaptureController controller,
  ) {
    final status = !state.hasAccess
        ? 'Permission not granted. Only custom coupons are available.'
        : state.allowedPackages.isEmpty
        ? 'Select allowed apps below. No apps are allowed by default.'
        : state.isActive
        ? 'Capturing new notifications from ${state.allowedPackages.length} allowed apps.'
        : 'Capture is paused.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Capture notifications'),
              subtitle: Text(status),
              value: state.isEnabled,
              onChanged:
                  controller.isSaving ||
                      (!state.isEnabled &&
                          (!state.hasAccess || state.allowedPackages.isEmpty))
                  ? null
                  : (enabled) => controller.setEnabled(enabled),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow Gmail, Outlook, or another mail app to capture new email '
              'notification previews. This does not read your inbox or fetch '
              'full emails. Only text exposed by Android can be captured. '
              'Email previews use the same notification permission; there is '
              'no separate email permission.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.isSaving ? null : _openAccessSettings,
              icon: Icon(
                state.hasAccess
                    ? Icons.verified_user_outlined
                    : Icons.lock_open,
              ),
              label: Text(
                state.hasAccess ? 'Manage notification access' : 'Grant access',
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _appList(
    NotificationCaptureState state,
    NotificationCaptureController controller,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final apps = controller.installedApps
        .where(
          (app) =>
              app.name.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query),
        )
        .toList();
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search installed apps',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${state.allowedPackages.length} allowed · '
              '${controller.installedApps.length} installed apps\n'
              'Removing an app also deletes its unsaved captures. '
              'Newly installed apps are never allowed automatically.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      if (apps.isEmpty)
        SliverToBoxAdapter(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                controller.isLoading
                    ? 'Loading installed apps…'
                    : 'No installed apps match.',
              ),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: SwitchListTile.adaptive(
                  key: ValueKey('allow-${app.packageName}'),
                  secondary: Icon(
                    app.isEmailApp ? Icons.mail_outline : Icons.apps,
                  ),
                  title: Text(app.name),
                  subtitle: Text(
                    '${app.packageName}${app.isEmailApp ? '\nEmail previews' : ''}',
                  ),
                  value: state.allowedPackages.contains(app.packageName),
                  onChanged: controller.isSaving
                      ? null
                      : (allowed) => controller.setAppAllowed(app, allowed),
                ),
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _inbox(
    NotificationCaptureState state,
    NotificationCaptureController controller,
  ) {
    if (state.notifications.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No captured messages yet.\n\n'
                'Select allowed apps, grant access, and enable capture. New '
                'notifications appear here even while OffersBucket is closed. '
                'Older notifications are not imported.\n\n'
                'Review a message to save it as an offer. Up to 200 recent '
                'captures are kept on this device.',
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: Text('${state.notifications.length} captured messages'),
              ),
              TextButton(
                onPressed: controller.isSaving ? null : _clearCaptures,
                child: const Text('Clear captures'),
              ),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: state.notifications.length,
        itemBuilder: (context, index) {
          final notification = state.notifications[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              key: ValueKey(notification.id),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          notification.isEmail
                              ? Icons.mail_outline
                              : Icons.notifications_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${notification.appName} · '
                            '${notification.isEmail ? 'Email' : 'App'}',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete captured message',
                          onPressed: controller.isSaving
                              ? null
                              : () => controller.deleteNotification(
                                  notification.id,
                                ),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatShortDate(notification.postedAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (notification.title.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        notification.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                    if (notification.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        notification.text,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: controller.isSaving
                          ? null
                          : () => _review(notification),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Review & save offer'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  }
}
