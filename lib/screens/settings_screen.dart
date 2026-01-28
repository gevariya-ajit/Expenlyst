import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/settings_service.dart';
import '../services/import_service.dart';
import '../services/sync_service.dart';
import '../services/local_auth_service.dart';
import '../widgets/sheet_picker_dialog.dart';
import '../widgets/sync_status_indicator.dart';

enum _SettingsSection {
  googleAccount,
  syncSettings,
  security,
  theme,
  currency,
  speechLanguage,
  importData,
  about,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isImporting = false;
  bool _appLockEnabled = false;
  bool _isAuthAvailable = false;
  _SettingsSection? _expandedSection;

  @override
  void initState() {
    super.initState();
    _loadAppLockSettings();
  }

  Future<void> _loadAppLockSettings() async {
    final isAvailable = await LocalAuthService.isAuthenticationAvailable();
    final isEnabled = await LocalAuthService.isAppLockEnabled();

    if (mounted) {
      setState(() {
        _isAuthAvailable = isAvailable;
        _appLockEnabled = isEnabled;
      });
    }
  }

  void _toggleSection(_SettingsSection section) {
    setState(() {
      if (_expandedSection == section) {
        _expandedSection = null;
      } else {
        _expandedSection = section;
      }
    });
  }

  Future<void> _toggleAppLock(bool enabled) async {
    if (enabled) {
      final success = await LocalAuthService.authenticate(
        reason: 'Authenticate to enable app lock',
      );

      if (success) {
        await LocalAuthService.setAppLockEnabled(true);
        setState(() => _appLockEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('App lock enabled'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed. App lock not enabled.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      final success = await LocalAuthService.authenticate(
        reason: 'Authenticate to disable app lock',
      );

      if (success) {
        await LocalAuthService.setAppLockEnabled(false);
        setState(() => _appLockEnabled = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('App lock disabled')),
          );
        }
      }
    }
  }

  Future<void> _importCsv() async {
    setState(() => _isImporting = true);

    try {
      final importService = ImportService();
      final result = await importService.importFromCsv();

      if (!mounted) return;

      if (result.success && result.expenses.isNotEmpty) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Import Expenses'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Found ${result.expenses.length} expenses to import.'),
                if (result.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${result.errors.length} rows had errors and will be skipped.',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Do you want to import these expenses?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import'),
              ),
            ],
          ),
        );

        if (confirm == true && mounted) {
          final expenseProvider = context.read<ExpenseProvider>();
          int imported = 0;
          for (final expense in result.expenses) {
            await expenseProvider.addExpense(expense);
            imported++;
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported $imported expenses'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: result.success ? null : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _handleSignIn() async {
    final syncProvider = context.read<SyncProvider>();
    final success = await syncProvider.signIn();

    if (!mounted) return;

    if (success) {
      final sheet = await SheetPickerDialog.show(context);
      if (sheet != null && mounted) {
        final expenseProvider = context.read<ExpenseProvider>();
        final allExpenses = await expenseProvider.getAllExpenses();

        if (allExpenses.isNotEmpty) {
          final action = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sync Data'),
              content: const Text(
                'You have local expenses. What would you like to do?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'upload'),
                  child: const Text('Upload to Sheet'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'download'),
                  child: const Text('Download from Sheet'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );

          if (action == 'upload' && mounted) {
            final result = await syncProvider.initialUpload();
            _showSyncResult(result, 'uploaded');
          } else if (action == 'download' && mounted) {
            final result = await syncProvider.restoreFromCloud();
            if (result.isSuccess) {
              expenseProvider.loadExpenses();
            }
            _showSyncResult(result, 'downloaded');
          }
        } else {
          final result = await syncProvider.restoreFromCloud();
          if (result.isSuccess) {
            expenseProvider.loadExpenses();
          }
          _showSyncResult(result, 'downloaded');
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign-in failed. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSyncResult(SyncStatus result, String action) {
    if (!mounted) return;

    if (result.isSuccess) {
      final count = action == 'uploaded' ? result.uploaded : result.downloaded;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully $action $count expenses'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${result.errorMessage ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'This will sign out and delete all local data. '
          'You can restore your data by signing in again and selecting your spreadsheet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final syncProvider = context.read<SyncProvider>();
      final expenseProvider = context.read<ExpenseProvider>();

      await syncProvider.signOut();
      await expenseProvider.loadExpenses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out and data cleared')),
        );
      }
    }
  }

  Future<void> _handleSyncNow() async {
    final syncProvider = context.read<SyncProvider>();
    final expenseProvider = context.read<ExpenseProvider>();

    final result = await syncProvider.syncNow();

    if (result.isSuccess && mounted) {
      await expenseProvider.loadExpenses();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync complete. Uploaded: ${result.uploaded}, Downloaded: ${result.downloaded}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted && !result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${result.errorMessage ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleChangeSheet() async {
    final sheet = await SheetPickerDialog.show(
      context,
      mode: SheetPickerMode.selectOnly,
    );

    if (sheet != null && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change Spreadsheet'),
          content: Text(
            'Switch to "${sheet.name}"? This will sync your data with the new sheet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await _handleSyncNow();
      }
    }
  }

  Future<void> _handleRestore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Cloud'),
        content: const Text(
          'This will replace all local data with data from the selected spreadsheet. '
          'Any local changes not yet synced will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final syncProvider = context.read<SyncProvider>();
      final expenseProvider = context.read<ExpenseProvider>();

      final result = await syncProvider.restoreFromCloud();

      if (result.isSuccess && mounted) {
        await expenseProvider.loadExpenses();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored ${result.downloaded} expenses from cloud'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: ${result.errorMessage ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer2<SettingsProvider, SyncProvider>(
        builder: (context, settingsProvider, syncProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Google Account Section
              _ExpandableSettingsCard(
                title: 'Google Account',
                subtitle: syncProvider.isSignedIn
                    ? syncProvider.userEmail ?? 'Signed in'
                    : 'Sign in to backup and sync',
                icon: Icons.account_circle,
                isExpanded: _expandedSection == _SettingsSection.googleAccount,
                onTap: () => _toggleSection(_SettingsSection.googleAccount),
                child: _buildGoogleAccountContent(syncProvider),
              ),

              // Sync Settings Section (only when signed in)
              if (syncProvider.isSignedIn)
                _ExpandableSettingsCard(
                  title: 'Sync Settings',
                  subtitle: 'Last: ${syncProvider.getLastSyncTimeFormatted()}',
                  icon: Icons.sync,
                  trailing: const SyncStatusIndicator(size: 16),
                  isExpanded: _expandedSection == _SettingsSection.syncSettings,
                  onTap: () => _toggleSection(_SettingsSection.syncSettings),
                  child: _buildSyncSettingsContent(syncProvider),
                ),

              // Security Section
              _ExpandableSettingsCard(
                title: 'Security',
                subtitle: _appLockEnabled ? 'App lock enabled' : 'Protect your data',
                icon: Icons.security,
                isExpanded: _expandedSection == _SettingsSection.security,
                onTap: () => _toggleSection(_SettingsSection.security),
                child: _buildSecurityContent(),
              ),

              // Theme Section
              _ExpandableSettingsCard(
                title: 'Theme',
                subtitle: settingsProvider.theme.displayName,
                icon: Icons.palette,
                trailing: _ThemeColorPreview(theme: settingsProvider.theme, small: true),
                isExpanded: _expandedSection == _SettingsSection.theme,
                onTap: () => _toggleSection(_SettingsSection.theme),
                child: _buildThemeContent(settingsProvider),
              ),

              // Currency Section
              _ExpandableSettingsCard(
                title: 'Currency',
                subtitle: '${settingsProvider.currencySymbol} ${settingsProvider.currency}',
                icon: Icons.attach_money,
                isExpanded: _expandedSection == _SettingsSection.currency,
                onTap: () => _toggleSection(_SettingsSection.currency),
                child: _buildCurrencyContent(settingsProvider),
              ),

              // Speech Language Section
              _ExpandableSettingsCard(
                title: 'Speech Language',
                subtitle: settingsProvider.speechLocale != null
                    ? settingsProvider.getSpeechLocaleDisplayName(settingsProvider.speechLocale!)
                    : 'Device default',
                icon: Icons.mic,
                isExpanded: _expandedSection == _SettingsSection.speechLanguage,
                onTap: () => _toggleSection(_SettingsSection.speechLanguage),
                child: _buildSpeechLanguageContent(settingsProvider),
              ),

              // Import Section
              _ExpandableSettingsCard(
                title: 'Import Data',
                subtitle: 'Import from CSV file',
                icon: Icons.upload_file,
                isExpanded: _expandedSection == _SettingsSection.importData,
                onTap: () => _toggleSection(_SettingsSection.importData),
                child: _buildImportContent(),
              ),

              // About Section
              _ExpandableSettingsCard(
                title: 'About',
                subtitle: 'Expenlyst v1.0.0',
                icon: Icons.info_outline,
                isExpanded: _expandedSection == _SettingsSection.about,
                onTap: () => _toggleSection(_SettingsSection.about),
                child: _buildAboutContent(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGoogleAccountContent(SyncProvider syncProvider) {
    if (!syncProvider.isSignedIn) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _handleSignIn,
          icon: Image.network(
            'https://www.google.com/favicon.ico',
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const Icon(Icons.login),
          ),
          label: const Text('Sign in with Google'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    return Row(
      children: [
        CircleAvatar(
          backgroundImage: syncProvider.userPhotoUrl != null
              ? NetworkImage(syncProvider.userPhotoUrl!)
              : null,
          child: syncProvider.userPhotoUrl == null
              ? Text(syncProvider.userInitials)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                syncProvider.userName ?? 'User',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                syncProvider.userEmail ?? '',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _handleSignOut,
          child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildSyncSettingsContent(SyncProvider syncProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Auto sync toggle
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Auto sync', style: TextStyle(fontSize: 16)),
                  Text(
                    'Sync automatically after each change',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: syncProvider.autoSyncEnabled,
              onChanged: (value) => syncProvider.setAutoSyncEnabled(value),
            ),
          ],
        ),
        const Divider(height: 24),

        // Sync now button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: syncProvider.syncState == SyncState.syncing
                ? null
                : _handleSyncNow,
            icon: syncProvider.syncState == SyncState.syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(
              syncProvider.syncState == SyncState.syncing
                  ? 'Syncing...'
                  : 'Sync Now',
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Selected sheet
        Row(
          children: [
            Icon(
              Icons.table_chart,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sheet: ${syncProvider.selectedSheetName ?? 'Not selected'}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _handleChangeSheet,
              child: const Text('Change'),
            ),
          ],
        ),
        const Divider(height: 24),

        // Restore button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: syncProvider.hasSelectedSheet ? _handleRestore : null,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Restore from Cloud'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Replace local data with cloud data',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSecurityContent() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.fingerprint,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Lock',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    _isAuthAvailable
                        ? 'Use biometric or device PIN'
                        : 'Not available on this device',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: _appLockEnabled,
              onChanged: _isAuthAvailable ? _toggleAppLock : null,
            ),
          ],
        ),
        if (!_isAuthAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set up a screen lock in device settings to enable.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThemeContent(SettingsProvider settingsProvider) {
    return Column(
      children: settingsProvider.availableThemes.map((theme) {
        final isSelected = settingsProvider.theme == theme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => settingsProvider.setTheme(theme),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? theme.primaryColor : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
                color: isSelected ? theme.primaryColor.withOpacity(0.05) : null,
              ),
              child: Row(
                children: [
                  _ThemeColorPreview(theme: theme),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      theme.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? theme.primaryColor : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: theme.primaryColor),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCurrencyContent(SettingsProvider settingsProvider) {
    return DropdownButtonFormField<String>(
      value: settingsProvider.currency,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: settingsProvider.supportedCurrencies.map((currency) {
        final symbol = settingsProvider.currencySymbols[currency];
        final name = settingsProvider.currencyNames[currency];
        return DropdownMenuItem(
          value: currency,
          child: Text('$symbol  $currency - $name'),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          settingsProvider.setCurrency(value);
        }
      },
    );
  }

  Widget _buildSpeechLanguageContent(SettingsProvider settingsProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select a language that matches your accent for better recognition.',
                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value: settingsProvider.speechLocale,
          decoration: InputDecoration(
            labelText: 'Speech Language',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Device default'),
            ),
            ...settingsProvider.supportedSpeechLocales.map((localeId) {
              final name = settingsProvider.getSpeechLocaleDisplayName(localeId);
              return DropdownMenuItem<String?>(
                value: localeId,
                child: Text(name),
              );
            }),
          ],
          onChanged: (value) {
            settingsProvider.setSpeechLocale(value);
          },
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Smart label matching',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Auto-correct labels based on your expense history',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Switch(
              value: settingsProvider.smartLabelMatching,
              onChanged: (value) {
                settingsProvider.setSmartLabelMatching(value);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImportContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CSV Format:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'date, label, amount, category',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Date format: dd-mm-yy',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isImporting ? null : _importCsv,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_isImporting ? 'Importing...' : 'Select CSV File'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutContent() {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Expenlyst'),
          subtitle: const Text('Version 1.0.0'),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.mic,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Voice Input'),
          subtitle: const Text(
            'Say "Coffee 5 dollars" or "Uber 12.50"',
          ),
        ),
      ],
    );
  }
}

class _ExpandableSettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;

  const _ExpandableSettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
    required this.isExpanded,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _ThemeColorPreview extends StatelessWidget {
  final AppTheme theme;
  final bool small;

  const _ThemeColorPreview({required this.theme, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 18.0 : 24.0;
    final overlap = small ? 10.0 : 14.0;
    // Total width: first circle full + 3 circles partially visible
    final totalWidth = size + (3 * (size - overlap));

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _ColorCircle(color: theme.primaryColor, size: size),
          ),
          Positioned(
            left: size - overlap,
            child: _ColorCircle(color: theme.primaryDarkColor, size: size),
          ),
          Positioned(
            left: (size - overlap) * 2,
            child: _ColorCircle(color: theme.secondaryColor, size: size),
          ),
          Positioned(
            left: (size - overlap) * 3,
            child: _ColorCircle(color: theme.accentColor, size: size),
          ),
        ],
      ),
    );
  }
}

class _ColorCircle extends StatelessWidget {
  final Color color;
  final double size;

  const _ColorCircle({required this.color, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
