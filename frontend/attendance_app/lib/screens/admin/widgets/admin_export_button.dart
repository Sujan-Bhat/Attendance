import 'package:flutter/material.dart';

import '../../../services/export_service.dart';

/// Export entry point: shows a PDF / Excel picker, then fetches the export
/// from the backend and downloads (web) or shares (mobile) the document.
class AdminExportButton extends StatefulWidget {
  /// Which dataset to export: students | teachers | classes | attendance.
  final String dataset;

  /// Optional scope, e.g. attendance exports for a single semester.
  final String? semester;

  final Color color;

  const AdminExportButton({
    super.key,
    required this.dataset,
    this.semester,
    this.color = const Color(0xFF007C91),
  });

  @override
  State<AdminExportButton> createState() => _AdminExportButtonState();
}

class _AdminExportButtonState extends State<AdminExportButton> {
  final ExportService _exportService = ExportService();
  bool _busy = false;

  Future<void> _pickAndExport() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Export as',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444)),
              title: const Text('PDF document'),
              subtitle: const Text('Formatted report, ready to print'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_rounded, color: Color(0xFF16A34A)),
              title: const Text('Excel workbook'),
              subtitle: const Text('Spreadsheet for further analysis'),
              onTap: () => Navigator.pop(ctx, 'xlsx'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (format == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _exportService.exportDataset(
        dataset: widget.dataset,
        format: format,
        semester: widget.semester,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_datasetLabel} exported as ${format == 'pdf' ? 'PDF' : 'Excel'}',
          ),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      debugPrint('Export failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export failed. Please try again.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _datasetLabel {
    switch (widget.dataset) {
      case 'students':
        return 'Student details';
      case 'teachers':
        return 'Teacher details';
      case 'classes':
        return 'Class details';
      case 'attendance':
        return 'Attendance details';
      default:
        return widget.dataset;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return IconButton(
      icon: Icon(Icons.file_download_outlined, color: widget.color, size: 24),
      tooltip: 'Export as PDF or Excel',
      onPressed: _pickAndExport,
    );
  }
}
