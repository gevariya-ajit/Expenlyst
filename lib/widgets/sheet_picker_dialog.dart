import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sync_provider.dart';
import '../services/sheets_service.dart';

enum SheetPickerMode {
  selectOrCreate,
  selectOnly,
}

class SheetPickerDialog extends StatefulWidget {
  final SheetPickerMode mode;

  const SheetPickerDialog({
    super.key,
    this.mode = SheetPickerMode.selectOrCreate,
  });

  static Future<SheetInfo?> show(
    BuildContext context, {
    SheetPickerMode mode = SheetPickerMode.selectOrCreate,
  }) {
    return showDialog<SheetInfo>(
      context: context,
      builder: (ctx) => SheetPickerDialog(mode: mode),
    );
  }

  @override
  State<SheetPickerDialog> createState() => _SheetPickerDialogState();
}

class _SheetPickerDialogState extends State<SheetPickerDialog> {
  bool _isLoading = true;
  bool _isCreating = false;
  final _nameController = TextEditingController(text: 'Expenlyst Expenses');

  @override
  void initState() {
    super.initState();
    _loadSheets();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSheets() async {
    setState(() => _isLoading = true);
    final syncProvider = context.read<SyncProvider>();
    await syncProvider.loadAvailableSheets();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createNewSheet() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    final syncProvider = context.read<SyncProvider>();
    final sheetId = await syncProvider.createNewSheet(name: name);

    if (mounted) {
      setState(() => _isCreating = false);
      if (sheetId != null) {
        Navigator.of(context).pop(SheetInfo(
          id: sheetId,
          name: name,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create spreadsheet'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _selectSheet(SheetInfo sheet) {
    final syncProvider = context.read<SyncProvider>();
    syncProvider.selectSheet(sheet);
    Navigator.of(context).pop(sheet);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, child) {
        return AlertDialog(
          title: Text(
            widget.mode == SheetPickerMode.selectOnly
                ? 'Select Spreadsheet'
                : 'Choose or Create Spreadsheet',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.mode == SheetPickerMode.selectOrCreate) ...[
                          Text(
                            'Create New',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Spreadsheet Name',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isCreating ? null : _createNewSheet,
                              icon: _isCreating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add),
                              label: Text(_isCreating ? 'Creating...' : 'Create New Spreadsheet'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'Existing Spreadsheets',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (syncProvider.availableSheets.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No Expenlyst spreadsheets found',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        else
                          ...syncProvider.availableSheets.map((sheet) {
                            final dateFormat = DateFormat('MMM d, y');
                            final modifiedStr = sheet.modifiedTime != null
                                ? dateFormat.format(sheet.modifiedTime!)
                                : 'Unknown';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.table_chart,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(sheet.name),
                                subtitle: Text('Modified: $modifiedStr'),
                                onTap: () => _selectSheet(sheet),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
