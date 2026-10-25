import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_page.dart';
import 'data/local_offer_store.dart';
import 'data/offer_repository.dart';
import 'models/offer.dart';
import 'models/notification_capture.dart';
import 'models/web_coupon_deal.dart';
import 'notification_capture_page.dart';
import 'services/auth_service.dart';
import 'services/expiry_reminder_service.dart';
import 'services/google_drive_backup_service.dart';
import 'services/notification_capture_controller.dart';
import 'services/notification_capture_service.dart';
import 'services/supabase_auth_service.dart';
import 'services/web_coupon_search_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_brand.dart';
import 'widgets/app_layout.dart';

const _ink = AppColors.ink;
const _muted = AppColors.muted;
const _line = AppColors.line;
const _compactCardsKey = 'offersbucket.compact_cards.v1';
const _listViewKey = 'offersbucket.list_view.v1';
const _expiryRemindersKey = 'offersbucket.expiry_reminders.v1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final store = await LocalOfferStore.create();
  final repository = OfferRepository(store: store, initialOffers: sampleOffers);
  repository.archiveExpired();

  AuthService? authService;
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    authService = SupabaseAuthService();
  }

  const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  final googleDriveService = GoogleDriveBackupService(
    iosClientId: googleIosClientId.isEmpty ? null : googleIosClientId,
    webClientId: googleWebClientId.isEmpty ? null : googleWebClientId,
  );

  runApp(
    MyApp(
      repository: repository,
      authService: authService,
      googleDriveService: googleDriveService,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.repository,
    this.authService,
    this.notificationCaptureService,
    this.webCouponSearchService,
    this.expiryReminderService,
    this.googleDriveService,
  });

  final OfferRepository? repository;
  final AuthService? authService;
  final NotificationCaptureService? notificationCaptureService;
  final WebCouponSearchService? webCouponSearchService;
  final ExpiryReminderService? expiryReminderService;
  final GoogleDriveBackupService? googleDriveService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OffersBucket',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: OffersBucketShell(
        repository: repository ?? OfferRepository(),
        authService: authService,
        notificationCaptureService: notificationCaptureService,
        webCouponSearchService: webCouponSearchService,
        expiryReminderService: expiryReminderService,
        googleDriveService: googleDriveService,
      ),
    );
  }
}

class OffersBucketShell extends StatefulWidget {
  const OffersBucketShell({
    super.key,
    required this.repository,
    this.authService,
    this.notificationCaptureService,
    this.webCouponSearchService,
    this.expiryReminderService,
    this.googleDriveService,
  });

  final OfferRepository repository;
  final AuthService? authService;
  final NotificationCaptureService? notificationCaptureService;
  final WebCouponSearchService? webCouponSearchService;
  final ExpiryReminderService? expiryReminderService;
  final GoogleDriveBackupService? googleDriveService;

  @override
  State<OffersBucketShell> createState() => _OffersBucketShellState();
}

class _OffersBucketShellState extends State<OffersBucketShell>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  int _selectedIndex = 0;
  String _selectedCategory = 'All';
  late final NotificationCaptureController _captureController;
  late final WebCouponSearchService _webCouponSearchService;
  late final ExpiryReminderService _expiryReminderService;
  bool _permissionDialogShown = false;
  bool _compactCards = false;
  bool _listView = false;
  bool _expiryReminders = true;
  bool _reminderPermissionGranted = true;

  OfferRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webCouponSearchService =
        widget.webCouponSearchService ?? ActuallyUsefulDealsService();
    _expiryReminderService =
        widget.expiryReminderService ?? ExpiryReminderService();
    _captureController = NotificationCaptureController(
      widget.notificationCaptureService ?? PlatformNotificationCaptureService(),
    )..addListener(_refresh);
    unawaited(_initializeCapture());
    unawaited(_initializeExpiryReminders());
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _compactCards = preferences.getBool(_compactCardsKey) ?? false;
          _listView = preferences.getBool(_listViewKey) ?? false;
          _expiryReminders = preferences.getBool(_expiryRemindersKey) ?? true;
        });
      }
    } catch (_) {
      // UI keeps safe defaults when platform preferences are unavailable.
    }
  }

  Future<void> _initializeExpiryReminders() async {
    await _loadPreferences();
    await _expiryReminderService.initialize();
    await _syncExpiryReminders(requestPermission: _expiryReminders);
  }

  Future<void> _setCompactCards(bool enabled) async {
    setState(() => _compactCards = enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_compactCardsKey, enabled);
    } catch (_) {
      // Keep current session behavior if persistence is unavailable.
    }
  }

  Future<void> _setListView(bool enabled) async {
    setState(() => _listView = enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_listViewKey, enabled);
    } catch (_) {
      // Keep current session behavior if persistence is unavailable.
    }
  }

  Future<void> _setExpiryReminders(bool enabled) async {
    setState(() => _expiryReminders = enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_expiryRemindersKey, enabled);
    } catch (_) {
      // Keep current session behavior if persistence is unavailable.
    }
    await _syncExpiryReminders(requestPermission: enabled);
  }

  Future<void> _syncExpiryReminders({bool requestPermission = false}) async {
    if (requestPermission) {
      _reminderPermissionGranted = await _expiryReminderService
          .requestPermission();
    }
    await _expiryReminderService.sync(
      _repository.activeOffers,
      enabled: _expiryReminders && _reminderPermissionGranted,
    );
    if (mounted) setState(() {});
  }

  Future<void> _initializeCapture() async {
    await _captureController.initialize();
    await _showMissingCapturePermissionDialog();
  }

  Future<void> _showMissingCapturePermissionDialog() async {
    if (!mounted ||
        _permissionDialogShown ||
        !_captureController.state.isSupported ||
        _captureController.state.hasAccess) {
      return;
    }
    _permissionDialogShown = true;

    final grantAccess = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Notification access not granted'),
        content: const Text(
          'OffersBucket cannot capture app notifications or email previews '
          'yet. Until Android notification access is granted, only custom '
          'coupons added manually will be available.\n\n'
          'Email preview capture uses this same Android permission; there is '
          'no separate inbox access permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Use custom coupons'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grant permission'),
          ),
        ],
      ),
    );
    if (grantAccess == true && mounted) {
      await _captureController.openAccessSettings();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_captureController.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureController.removeListener(_refresh);
    _captureController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _openCapture({bool showInbox = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => NotificationCapturePage(
          controller: _captureController,
          showInbox: showInbox,
          onReview: _reviewCapture,
        ),
      ),
    );
    _refresh();
  }

  Future<bool> _reviewCapture(CapturedNotification notification) async {
    if (_repository.isCaptureSaved(notification.id)) return true;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Review captured offer')),
          body: AppBackground(
            child: SafeArea(
              child: AddOfferPage(
                repository: _repository,
                capturedNotification: notification,
                onSaved: () => Navigator.pop(context, true),
              ),
            ),
          ),
        ),
      ),
    );
    _refresh();
    return saved ?? false;
  }

  void _openOffer(Offer offer) {
    showDialog<void>(
      context: context,
      barrierColor: _ink.withAlpha(120),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: OfferDetailsSheet(
            offer: offer,
            onFavorite: () {
              _repository.toggleFavorite(offer.id);
              Navigator.pop(context);
              _refresh();
            },
            onCopied: () {
              ScaffoldMessenger.of(
                this.context,
              ).showSnackBar(const SnackBar(content: Text('Code copied')));
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        repository: _repository,
        searchController: _searchController,
        selectedCategory: _selectedCategory,
        onCategoryChanged: (category) {
          setState(() => _selectedCategory = category);
        },
        onSearchChanged: (_) => setState(() {}),
        onFavorite: (offer) {
          _repository.toggleFavorite(offer.id);
          _refresh();
        },
        onOfferTap: _openOffer,
        onAddOffer: () => setState(() => _selectedIndex = 2),
        compactCards: _compactCards,
        listView: _listView,
        onListViewChanged: _setListView,
      ),
      ExplorePage(searchService: _webCouponSearchService),
      AddOfferPage(
        repository: _repository,
        onSaved: () {
          setState(() {
            _selectedIndex = 0;
            _selectedCategory = 'All';
          });
          unawaited(_syncExpiryReminders());
        },
      ),
      ArchivePage(
        repository: _repository,
        onOfferTap: _openOffer,
        compactCards: _compactCards,
      ),
      SettingsPage(
        repository: _repository,
        authService: widget.authService,
        googleDriveService: widget.googleDriveService,
        onOffersImported: () {
          _refresh();
          unawaited(_syncExpiryReminders());
        },
        captureController: _captureController,
        onOpenCapture: () => _openCapture(),
        compactCards: _compactCards,
        onCompactCardsChanged: _setCompactCards,
        expiryReminders: _expiryReminders,
        reminderPermissionGranted: _reminderPermissionGranted,
        onExpiryRemindersChanged: _setExpiryReminders,
      ),
    ];

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.maxPageWidth,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: pages[_selectedIndex],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _line)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Add offer',
            ),
            NavigationDestination(
              icon: Icon(Icons.archive_outlined),
              selectedIcon: Icon(Icons.archive),
              label: 'Archive',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.searchController,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onFavorite,
    required this.onOfferTap,
    required this.onAddOffer,
    this.compactCards = false,
    required this.listView,
    required this.onListViewChanged,
  });

  final OfferRepository repository;
  final TextEditingController searchController;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Offer> onFavorite;
  final ValueChanged<Offer> onOfferTap;
  final VoidCallback onAddOffer;
  final bool compactCards;
  final bool listView;
  final ValueChanged<bool> onListViewChanged;

  @override
  Widget build(BuildContext context) {
    final categories = _categories(repository.activeOffers);
    final searched = repository.search(
      searchController.text,
      sort: OfferSort.expiry,
    );
    final offers = selectedCategory == 'All'
        ? searched
        : searched
              .where((offer) => offer.category == selectedCategory)
              .toList();
    return AppPageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(text: 'great deals.\n'),
                      TextSpan(
                        text: 'one bucket.',
                        style: TextStyle(fontWeight: FontWeight.w300),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
              const SizedBox(width: 16),
              const AppBrandMark(size: 36),
            ],
          ),
          const SizedBox(height: 24),
          _SearchField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 18),
          _CategoryChips(
            categories: categories,
            selected: selectedCategory,
            onSelected: onCategoryChanged,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${offers.length} coupon${offers.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.grid_view_outlined),
                    tooltip: 'Grid view',
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_list_outlined),
                    tooltip: 'List view',
                  ),
                ],
                selected: {listView},
                onSelectionChanged: (selection) =>
                    onListViewChanged(selection.first),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Add coupon',
                onPressed: onAddOffer,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (offers.isEmpty)
            EmptyState(
              icon: Icons.search_off_rounded,
              title: searchController.text.trim().isEmpty
                  ? 'No coupons saved'
                  : 'No coupons found',
              message: searchController.text.trim().isEmpty
                  ? 'Add a coupon to start.'
                  : 'Try another search.',
              actionLabel: searchController.text.trim().isEmpty
                  ? 'Add an offer'
                  : null,
              onAction: onAddOffer,
            )
          else if (listView)
            Column(
              children: [
                for (final offer in offers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: OfferCard(
                      offer: offer,
                      onTap: () => onOfferTap(offer),
                      onFavorite: () => onFavorite(offer),
                      compact: compactCards,
                    ),
                  ),
              ],
            )
          else
            AppCardGrid(
              columns: 2,
              children: [
                for (final offer in offers)
                  OfferCard(
                    offer: offer,
                    onTap: () => onOfferTap(offer),
                    onFavorite: () => onFavorite(offer),
                    compact: compactCards,
                    minimal: true,
                  ),
              ],
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, required this.searchService});

  final WebCouponSearchService searchService;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _searchController = TextEditingController();
  List<WebCouponDeal> _deals = const [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final deals = await widget.searchService.search(query);
      if (!mounted) return;
      setState(() => _deals = deals);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openDeal(WebCouponDeal deal) async {
    final uri = Uri.tryParse(deal.url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open deal link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CompactHeader(title: 'Explore web deals'),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search Nike, travel, charger…',
              prefixIcon: const Icon(Icons.travel_explore),
              suffixIcon: IconButton(
                onPressed: _isLoading ? null : _search,
                tooltip: 'Search web',
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_isLoading) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _InfoPanel(
              icon: Icons.cloud_off_outlined,
              title: 'Web search unavailable',
              message: _error!,
            ),
          ],
          if (!_isLoading && _error == null && _deals.isEmpty) ...[
            const SizedBox(height: 12),
            const EmptyState(
              icon: Icons.search,
              title: 'Search the web for deals',
              message: 'Enter a brand, product, or category above.',
            ),
          ],
          if (_deals.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '${_deals.length} web deal${_deals.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            AppCardGrid(
              children: [
                for (final deal in _deals)
                  _WebDealCard(deal: deal, onOpen: () => _openDeal(deal)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class AddOfferPage extends StatefulWidget {
  const AddOfferPage({
    super.key,
    required this.repository,
    required this.onSaved,
    this.capturedNotification,
  });

  final OfferRepository repository;
  final VoidCallback onSaved;
  final CapturedNotification? capturedNotification;

  @override
  State<AddOfferPage> createState() => _AddOfferPageState();
}

class _AddOfferPageState extends State<AddOfferPage> {
  final _formKey = GlobalKey<FormState>();
  final _brandController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _originalMessageController = TextEditingController();
  final _codeController = TextEditingController();
  String _category = 'Shopping';
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final notification = widget.capturedNotification;
    if (notification == null) return;
    _brandController.text = notification.suggestedBrand;
    _titleController.text = notification.suggestedTitle;
    _descriptionController.text = notification.text;
    _originalMessageController.text = notification.originalMessage;
    _codeController.text = notification.suggestedCode;
  }

  @override
  void dispose() {
    _brandController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _originalMessageController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date != null) setState(() => _validUntil = date);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    widget.repository.addCustomOffer(
      brand: _brandController.text,
      title: _titleController.text,
      description: _descriptionController.text,
      originalMessage: _originalMessageController.text,
      captureId: widget.capturedNotification?.id,
      code: _codeController.text,
      category: _category,
      validUntil: _validUntil,
      colorValue: _categoryColor(_category).toARGB32(),
      iconKey: _categoryIconKey(_category),
      source: widget.capturedNotification == null
          ? 'Custom'
          : '${widget.capturedNotification!.appName} '
                '${widget.capturedNotification!.isEmail ? 'email' : 'notification'}',
    );
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScroll(
      maxWidth: AppLayout.maxFormWidth,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _CompactHeader(
              title: 'Add an offer',
              subtitle: 'Save a deal.',
            ),
            const SizedBox(height: 18),
            if (widget.capturedNotification != null) ...[
              const Text(
                'Review the suggested details and set the actual expiry date. '
                'The default date is not extracted from the message.',
              ),
              const SizedBox(height: 16),
            ],
            _FormSection(
              title: 'Offer basics',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormField(
                    controller: _brandController,
                    label: 'Brand',
                    hint: 'e.g. Nike',
                    icon: Icons.storefront_outlined,
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _titleController,
                    label: 'Offer title',
                    hint: 'e.g. 25% off',
                    icon: Icons.local_offer_outlined,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items:
                        const [
                              'Shopping',
                              'Fashion',
                              'Food & Drink',
                              'Travel',
                              'Wellness',
                              'Entertainment',
                            ]
                            .map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _FormSection(
              title: 'Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormField(
                    controller: _descriptionController,
                    label: 'Description',
                    hint: 'Optional notes',
                    icon: Icons.notes_outlined,
                    maxLines: 3,
                    requiredField: false,
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _originalMessageController,
                    label: 'Original message',
                    hint: 'Paste notification or email text',
                    icon: Icons.message_outlined,
                    maxLines: 3,
                    requiredField: false,
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _codeController,
                    label: 'Promo code',
                    hint: 'Optional',
                    icon: Icons.confirmation_number_outlined,
                    requiredField: false,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Valid until',
                          prefixIcon: Icon(Icons.event_outlined),
                          suffixIcon: Icon(Icons.chevron_right),
                        ),
                        child: Text(
                          _formatDate(_validUntil),
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Saving…' : 'Save offer'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class ArchivePage extends StatelessWidget {
  const ArchivePage({
    super.key,
    required this.repository,
    required this.onOfferTap,
    this.compactCards = false,
  });

  final OfferRepository repository;
  final ValueChanged<Offer> onOfferTap;
  final bool compactCards;

  @override
  Widget build(BuildContext context) {
    final archived = repository.archivedOffers;
    return AppPageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CompactHeader(title: 'Archive'),
          const SizedBox(height: 8),
          Text(
            '${archived.length} archived',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (archived.isEmpty)
            const EmptyState(
              icon: Icons.archive_outlined,
              title: 'Archive is clear',
              message: 'Expired offers appear here.',
            )
          else
            AppCardGrid(
              children: [
                for (final offer in archived)
                  OfferCard(
                    offer: offer,
                    onTap: () => onOfferTap(offer),
                    showArchiveBadge: true,
                    compact: compactCards,
                  ),
              ],
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    this.authService,
    required this.onOffersImported,
    this.captureController,
    this.onOpenCapture,
    this.googleDriveService,
    required this.compactCards,
    required this.onCompactCardsChanged,
    required this.expiryReminders,
    required this.reminderPermissionGranted,
    required this.onExpiryRemindersChanged,
  });

  final OfferRepository repository;
  final AuthService? authService;
  final VoidCallback onOffersImported;
  final NotificationCaptureController? captureController;
  final VoidCallback? onOpenCapture;
  final GoogleDriveBackupService? googleDriveService;
  final bool compactCards;
  final ValueChanged<bool> onCompactCardsChanged;
  final bool expiryReminders;
  final bool reminderPermissionGranted;
  final ValueChanged<bool> onExpiryRemindersChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _openAccount() async {
    await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: AuthPage(authService: widget.authService),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _importOffers() async {
    try {
      if (widget.googleDriveService?.isConfigured ?? false) {
        final offers = await widget.googleDriveService!.loadLatestBackup();
        final count = widget.repository.importOffers(offers);
        widget.repository.archiveExpired();
        widget.onOffersImported();
        if (mounted) _showMessage('$count offers loaded from Google Drive');
        return;
      }

      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final offers = GoogleDriveBackupService.decodeOffers(utf8.decode(bytes));
      final count = widget.repository.importOffers(offers);
      widget.repository.archiveExpired();
      widget.onOffersImported();
      if (mounted) _showMessage('$count offers loaded');
    } on FormatException {
      if (mounted) _showMessage('Invalid offers file');
    } on TypeError {
      if (mounted) _showMessage('Invalid offers file');
    } on GoogleDriveConfigurationException catch (error) {
      if (mounted) _showMessage(error.message);
    } on GoogleDriveAuthorizationException catch (error) {
      if (mounted) _showMessage(error.message);
    } on GoogleDriveBackupNotFoundException catch (error) {
      if (mounted) _showMessage(error.message);
    } on GoogleDriveRequestException catch (error) {
      if (mounted) _showMessage(error.message);
    } on GoogleSignInException catch (error) {
      if (mounted) {
        _showMessage(
          'Google sign-in failed: ${error.description ?? error.code.name}',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Google Drive error: $error');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScroll(
      maxWidth: AppLayout.maxFormWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CompactHeader(title: 'Settings'),
          const SizedBox(height: 26),
          if (widget.captureController != null) ...[
            const _SettingsLabel('CAPTURE'),
            _SettingsCard(
              icon: Icons.notifications_active_outlined,
              title: 'App & email notifications',
              subtitle: '',
              trailing: TextButton(
                onPressed: widget.onOpenCapture,
                child: Text(
                  widget.captureController!.state.hasAccess
                      ? 'Manage'
                      : 'Grant again',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SettingsCard(
            icon: Icons.notifications_none_rounded,
            title: 'Expiry reminders',
            subtitle: !widget.reminderPermissionGranted
                ? 'Notification permission not granted.'
                : 'Scheduled one day before coupon expiry.',
            trailing: Switch(
              value: widget.expiryReminders,
              onChanged: widget.onExpiryRemindersChanged,
            ),
          ),
          _SettingsCard(
            icon: Icons.view_agenda_outlined,
            title: 'Compact cards',
            subtitle: 'Show more offers.',
            trailing: Switch(
              value: widget.compactCards,
              onChanged: widget.onCompactCardsChanged,
            ),
          ),
          _SettingsCard(
            icon: Icons.cloud_sync_outlined,
            title: 'Account & sync',
            subtitle: widget.authService == null
                ? 'Add Supabase for sync.'
                : widget.authService!.email ?? 'Sign in to sync.',
            trailing: TextButton(
              onPressed: _openAccount,
              child: const Text('Open'),
            ),
          ),
          const SizedBox(height: 16),
          const _SettingsLabel('IMPORT'),
          _SettingsCard(
            icon: Icons.cloud_download_outlined,
            title: 'Import offers',
            subtitle: 'From Google Drive or a JSON file.',
            trailing: TextButton(
              onPressed: _importOffers,
              child: const Text('Import'),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class OfferDetailsSheet extends StatelessWidget {
  const OfferDetailsSheet({
    super.key,
    required this.offer,
    required this.onFavorite,
    required this.onCopied,
  });

  final Offer offer;
  final VoidCallback onFavorite;
  final VoidCallback onCopied;

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: offer.code));
    if (context.mounted) onCopied();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Offer details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close offer details',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailText(label: 'Brand', value: offer.brand),
          _DetailText(label: 'Title', value: offer.title),
          if (offer.description.isNotEmpty)
            _DetailText(label: 'Description', value: offer.description),
          if (offer.originalMessage.isNotEmpty)
            _DetailText(
              label: 'Original message',
              value: offer.originalMessage,
            ),
          _DetailText(
            label: 'Code',
            value: offer.code.isEmpty ? '—' : offer.code,
          ),
          _DetailText(
            label: 'Valid until',
            value: _formatDate(offer.validUntil),
          ),
          const SizedBox(height: 12),
          OverflowBar(
            alignment: MainAxisAlignment.start,
            spacing: 12,
            overflowSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: offer.code.isEmpty ? null : () => _copyCode(context),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy'),
              ),
              OutlinedButton(
                onPressed: onFavorite,
                child: Text(offer.isFavorite ? 'Favorited' : 'Favorite'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailText extends StatelessWidget {
  const _DetailText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        Icon(icon, color: _muted, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WebDealCard extends StatelessWidget {
  const _WebDealCard({required this.deal, required this.onOpen});

  final WebCouponDeal deal;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Card(
      child: SizedBox(
        height: AppLayout.cardHeight(context),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: (scaler.scale(12) * 1.4 + 6).clamp(
                  24.0,
                  double.infinity,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    deal.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: scaler.scale(20) * 1.25 * 2,
                child: Text(
                  deal.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                deal.description.isEmpty ? deal.category : deal.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (deal.price.isNotEmpty) ...[
                    Expanded(
                      child: Text(
                        deal.price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Flexible(
                    child: OutlinedButton(
                      onPressed: onOpen,
                      child: const Text('Open deal'),
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
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    Widget? actionButton;
    if (onAction != null) {
      final label = actionLabel;
      if (label != null && label.isNotEmpty) {
        actionButton = FilledButton(onPressed: onAction, child: Text(label));
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: _muted),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          if (message?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(color: _muted, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionButton != null) ...[
            const SizedBox(height: 16),
            actionButton,
          ],
        ],
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle?.isNotEmpty ?? false) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        const AppBrandMark(size: 36),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search coupons',
        prefixIcon: const Icon(Icons.search),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (index, category) in categories.indexed)
            Padding(
              padding: EdgeInsets.only(
                right: index == categories.length - 1 ? 0 : 8,
              ),
              child: ChoiceChip(
                label: Text(
                  category,
                  style: TextStyle(
                    color: selected == category ? Colors.white : _ink,
                  ),
                ),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: _muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.requiredField = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final bool requiredField;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    textCapitalization: TextCapitalization.sentences,
    validator: requiredField
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      alignLabelWithHint: maxLines > 1,
    ),
  );
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 9),
    child: Text(
      label,
      style: const TextStyle(
        color: _muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
        leading: Icon(icon, color: _muted, size: 22),
        title: Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: subtitle.isNotEmpty
            ? Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              )
            : null,
        trailing: trailing,
      ),
    ),
  );
}

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.onTap,
    this.onFavorite,
    this.showArchiveBadge = false,
    this.compact = false,
    this.minimal = false,
  });

  final Offer offer;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool showArchiveBadge;
  final bool compact;
  final bool minimal;

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: offer.code));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleSize = minimal
        ? (compact ? 13.0 : 15.0)
        : (compact ? 17.0 : 20.0);
    final brandHeight = scaler.scale(11) * 1.4 + 2;
    final minimalTitleHeight = scaler.scale(titleSize) * 1.3 * 2 + 2;
    final footerHeight = (scaler.scale(11) * 1.4 + 12).clamp(
      44.0,
      double.infinity,
    );
    final radius = BorderRadius.circular(minimal ? 12 : 16);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          height: minimal
              ? brandHeight + minimalTitleHeight + footerHeight + 40
              : AppLayout.cardHeight(context, compact: compact),
          child: Padding(
            padding: EdgeInsets.all(minimal ? 12 : (compact ? 16 : 20)),
            child: minimal
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: brandHeight,
                        child: Text(
                          offer.brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: minimalTitleHeight,
                        child: Text(
                          offer.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _ink,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: footerHeight,
                        child: offer.code.isNotEmpty
                            ? Tooltip(
                                message: 'Copy ${offer.code}',
                                child: InkWell(
                                  onTap: () => _copyCode(context),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          offer.code,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.copy_outlined,
                                        size: 14,
                                        color: _muted,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'No code needed',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: (scaler.scale(12) * 1.4 + 6).clamp(
                          24.0,
                          double.infinity,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                offer.brand,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            if (showArchiveBadge)
                              const _SmallBadge(label: 'ARCHIVED'),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 8),
                      SizedBox(
                        height: scaler.scale(titleSize) * 1.25 * 2,
                        child: Text(
                          offer.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _ink,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.4,
                            height: 1.25,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 8),
                      Text(
                        offer.description.isEmpty
                            ? (showArchiveBadge
                                  ? 'Archived offer'
                                  : _expiryLabel(offer.validUntil))
                            : offer.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _muted,
                          fontSize: compact ? 12 : 14,
                          height: 1.4,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(height: compact ? 10 : 12),
                      Row(
                        children: [
                          Expanded(
                            child: offer.code.isNotEmpty
                                ? _CouponCodePill(
                                    code: offer.code,
                                    onTap: () => _copyCode(context),
                                  )
                                : Text(
                                    'No code needed',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.arrow_outward_rounded,
                            color: _muted,
                            size: 18,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CouponCodePill extends StatelessWidget {
  const _CouponCodePill({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Copy $code',
    child: Material(
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy_outlined, size: 16, color: _ink),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Color _categoryColor(String category) {
  switch (category) {
    case 'Shopping':
      return _ink;
    case 'Fashion':
      return const Color(0xFF9333EA);
    case 'Food & Drink':
      return const Color(0xFFDC2626);
    case 'Travel':
      return const Color(0xFF0891B2);
    case 'Wellness':
      return const Color(0xFF15803D);
    case 'Entertainment':
      return const Color(0xFFD97706);
    default:
      return _ink;
  }
}

String _categoryIconKey(String category) {
  switch (category) {
    case 'Shopping':
      return 'storefront';
    case 'Fashion':
      return 'checkroom';
    case 'Food & Drink':
      return 'restaurant';
    case 'Travel':
      return 'flight';
    case 'Wellness':
      return 'spa';
    case 'Entertainment':
      return 'movie';
    default:
      return 'category';
  }
}

String _expiryLabel(DateTime validUntil) {
  final now = DateTime.now();
  final difference = validUntil.difference(now).inDays;
  if (difference < 0) {
    return 'Expired';
  }
  if (difference == 0) {
    return 'Expires today';
  }
  if (difference == 1) {
    return 'Expires tomorrow';
  }
  return 'Expires in $difference days';
}

List<String> _categories(List<Offer> offers) {
  final set = <String>{'All'};
  for (final offer in offers) {
    set.add(offer.category);
  }
  return set.toList();
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
