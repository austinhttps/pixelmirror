// lib/ui/views/app_drawer_panel.dart
import 'package:fluent_ui/fluent_ui.dart';
import '../../models/contract_models.dart';
import '../../network/adb_manager.dart';

class AppDrawerPanel extends StatefulWidget {
  final AdbManager adbManager;

  const AppDrawerPanel({super.key, required this.adbManager});

  @override
  State<AppDrawerPanel> createState() => _AppDrawerPanelState();
}

class _AppDrawerPanelState extends State<AppDrawerPanel> {
  final TextEditingController _searchController = TextEditingController();
  List<AppPackageModel> _allPackages = [];
  List<AppPackageModel> _filteredPackages = [];
  bool _isLoading = true;
  String? _recentlyLaunched;

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
    _searchController.addListener(_filterPackages);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _isLoading = true);
    final packages = await widget.adbManager.queryThirdPartyPackages();
    if (mounted) {
      setState(() {
        _allPackages = packages;
        _filteredPackages = packages;
        _isLoading = false;
      });
    }
  }

  void _filterPackages() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPackages = _allPackages;
      } else {
        _filteredPackages = _allPackages.where((p) {
          return p.label.toLowerCase().contains(query) ||
              p.packageName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _launchApp(AppPackageModel app) async {
    setState(() => _recentlyLaunched = app.packageName);
    final success = await widget.adbManager.launchApp(app.packageName);
    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) {
          return InfoBar(
            title: Text(success ? 'Launched ${app.label}' : 'Failed to launch'),
            content: Text(app.packageName),
            severity: success ? InfoBarSeverity.success : InfoBarSeverity.error,
            onClose: close,
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Pixel 10 App Drawer'),
        commandBar: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              child: TextBox(
                controller: _searchController,
                placeholder: 'Search apps...',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(FluentIcons.search),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: _isLoading ? null : _loadInstalledApps,
            ),
          ],
        ),
      ),
      content: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProgressRing(),
                  SizedBox(height: 16),
                  Text('Querying third-party apps via ADB...'),
                ],
              ),
            )
          : _filteredPackages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.package, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No third-party packages found',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Button(
                        onPressed: _loadInstalledApps,
                        child: const Text('Re-query ADB'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.6,
                  ),
                  itemCount: _filteredPackages.length,
                  itemBuilder: (context, index) {
                    final app = _filteredPackages[index];
                    final isLaunching = _recentlyLaunched == app.packageName;

                    return Card(
                      padding: const EdgeInsets.all(12),
                      borderRadius: BorderRadius.circular(10),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _launchApp(app),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    FluentIcons.app_icon_default,
                                    color: Colors.blue,
                                  ),
                                ),
                                const Spacer(),
                                if (isLaunching)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: ProgressRing(strokeWidth: 2),
                                  )
                                else
                                  const Icon(
                                    FluentIcons.open_in_new_window,
                                    color: Colors.grey,
                                  ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  app.packageName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[100],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
