import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/web_utils_stub.dart' if (dart.library.js_interop) '../../../utils/web_utils.dart';

import '../../../services/bulk_students_service.dart';
import '../../../services/class_service.dart';
import 'dialog_colors.dart';

enum _BulkPhase { setup, review }

/// The "Excel Upload" division of the Add Student dialog.
///
/// Guides the admin through: set a default password -> download the template
/// -> pick an .xlsx file -> validate (inline corrections) -> confirm create.
class BulkStudentsTab extends StatefulWidget {
  final ClassService classService;
  final VoidCallback onStudentCreated;

  const BulkStudentsTab({
    super.key,
    required this.classService,
    required this.onStudentCreated,
  });

  @override
  State<BulkStudentsTab> createState() => _BulkStudentsTabState();
}

class _BulkStudentsTabState extends State<BulkStudentsTab> {
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  String? _passwordError;

  _BulkPhase _phase = _BulkPhase.setup;
  bool _busy = false;
  String _fileName = '';
  Uint8List? _fileBytes;

  List<BulkRow> _rows = [];
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _emailControllers = [];
  final List<TextEditingController> _semesterControllers = [];
  String? _batchError;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _disposeRowControllers();
    super.dispose();
  }

  void _disposeRowControllers() {
    for (final c in [..._nameControllers, ..._emailControllers, ..._semesterControllers]) {
      c.dispose();
    }
    _nameControllers.clear();
    _emailControllers.clear();
    _semesterControllers.clear();
  }

  bool get _hasFile => _fileName.isNotEmpty && _fileBytes != null;
  bool get _passwordValid => _passwordController.text.trim().length >= 6;
  int get _validCount => _rows.where((r) => !r.hasErrors).length;
  int get _errorCount => _rows.length - _validCount;
  bool get _allValid => _rows.isNotEmpty && _errorCount == 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_phase == _BulkPhase.setup) ..._buildSetupContent(),
                if (_phase == _BulkPhase.review) _buildReviewContent(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_phase == _BulkPhase.review) _buildReviewSummary(),
        const SizedBox(height: 8),
        _buildFooter(),
      ],
    );
  }

  // ---- Setup phase -------------------------------------------------------

  List<Widget> _buildSetupContent() {
    return [
      const Text(
        'Add multiple students at once from an Excel file matching the template.',
        style: TextStyle(fontSize: 14, color: DialogColors.textMuted),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        obscureText: _obscurePassword,
        style: const TextStyle(fontSize: 17),
        onChanged: (_) => setState(() => _passwordError = null),
        decoration: InputDecoration(
          labelText: 'Default password (min 6 chars)',
          helperText: 'Applied to every student in the file',
          errorText: _passwordError,
          prefixIcon: const Icon(Icons.lock_outline, size: 26),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.grey,
              size: 24,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _downloadTemplate,
              icon: const Icon(Icons.download_outlined, size: 20),
              label: const Text('Download Template'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DialogColors.tealDark,
                side: const BorderSide(color: DialogColors.tealDark),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.upload_file_outlined, size: 20),
              label: const Text('Choose Excel File'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DialogColors.tealDark,
                side: const BorderSide(color: DialogColors.tealDark),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: DialogColors.teal.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 22, color: DialogColors.tealDark),
            const SizedBox(width: 10),
            Expanded(
              child: _hasFile
                  ? Text(
                      _fileName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    )
                  : const Text(
                      'No file selected yet',
                      style: TextStyle(fontSize: 14, color: DialogColors.textMuted),
                    ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Template columns: Name, Email, Semester.\nUse one row per student. A blank row is ignored.',
        style: TextStyle(fontSize: 12.5, color: DialogColors.textMuted),
      ),
    ];
  }

  // ---- Review phase ------------------------------------------------------

  Widget _buildReviewSummary() {
    return Row(
      children: [
        Icon(_allValid ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: _allValid ? DialogColors.tealDark : DialogColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _allValid ? '$_validCount students ready to add' : '$_errorCount of ${_rows.length} rows need attention',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _allValid ? DialogColors.tealDark : DialogColors.danger,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewContent() {
    if (_batchError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DialogColors.dangerBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: DialogColors.danger, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_batchError!,
                  style: const TextStyle(color: DialogColors.danger, fontSize: 13.5)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _batchError = null;
                _phase = _BulkPhase.setup;
              }),
              child: const Text('Choose another file'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTableHeader(),
        const SizedBox(height: 6),
        for (var i = 0; i < _rows.length; i++) ...[
          _buildEditableRow(i),
          if (i < _rows.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildTableHeader() {
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DialogColors.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: const [
          SizedBox(width: 46, child: Text('ROW', style: style)),
          Expanded(child: Text('NAME', style: style)),
          SizedBox(width: 8),
          Expanded(child: Text('EMAIL', style: style)),
          SizedBox(width: 8),
          SizedBox(width: 120, child: Text('SEMESTER', style: style)),
        ],
      ),
    );
  }

  Widget _buildEditableRow(int index) {
    final row = _rows[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '${row.row}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DialogColors.textMuted),
            ),
          ),
        ),
        Expanded(child: _buildCell(index, row, 'name', _nameControllers[index])),
        const SizedBox(width: 8),
        Expanded(child: _buildCell(index, row, 'email', _emailControllers[index])),
        const SizedBox(width: 8),
        SizedBox(width: 120, child: _buildCell(index, row, 'semester', _semesterControllers[index])),
      ],
    );
  }

  Widget _buildCell(int index, BulkRow row, String field, TextEditingController controller) {
    final error = row.errors[field];
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        errorText: error,
        errorMaxLines: 2,
        filled: error != null,
        fillColor: error != null ? DialogColors.dangerBg : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error != null ? DialogColors.danger : Colors.grey.shade400,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error != null ? DialogColors.danger : DialogColors.tealDark,
            width: 2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error != null ? DialogColors.danger : Colors.grey.shade400,
          ),
        ),
      ),
      onChanged: (_) => setState(() => row.errors.remove(field)),
    );
  }

  // ---- Footer actions ----------------------------------------------------

  Widget _buildFooter() {
    final String primaryLabel;
    final bool primaryEnabled;
    switch (_phase) {
      case _BulkPhase.setup:
        primaryLabel = 'Upload & Validate';
        primaryEnabled = _hasFile && _passwordValid && !_busy;
      case _BulkPhase.review:
        primaryLabel = _allValid ? 'Add $_validCount Students' : 'Re-validate';
        primaryEnabled = !_busy && (_allValid || _rows.isNotEmpty);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: primaryEnabled ? _handlePrimaryAction : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: DialogColors.tealDark,
            foregroundColor: Colors.white,
            disabledBackgroundColor: DialogColors.tealDark.withValues(alpha: 0.35),
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(primaryLabel),
        ),
      ],
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_passwordError != null) return;
    switch (_phase) {
      case _BulkPhase.setup:
        await _uploadAndValidate();
      case _BulkPhase.review:
        if (_allValid) {
          await _createStudents();
        } else {
          await _revalidate();
        }
    }
  }

  // ---- File handling -----------------------------------------------------

  Future<void> _downloadTemplate() async {
    try {
      final data = await rootBundle.load('assets/templates/student_add_template.xlsx');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (kIsWeb) {
        downloadWeb(bytes, 'student_add_template.xlsx');
      } else {
        await FilePicker.platform.saveFile(
          fileName: 'student_add_template.xlsx',
          bytes: bytes,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template downloaded. Fill it and upload it here.'),
            backgroundColor: DialogColors.tealDark,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not download the template'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _fileBytes = file.bytes;
        _batchError = null;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that file'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ---- Service calls -----------------------------------------------------

  Future<void> _uploadAndValidate() async {
    final password = _passwordController.text.trim();
    if (password.length < 6) {
      setState(() => _passwordError = 'At least 6 characters');
      return;
    }
    setState(() {
      _busy = true;
      _batchError = null;
    });
    final result = await BulkStudentsService().validateUpload(
      fileBytes: _fileBytes!,
      fileName: _fileName,
      defaultPassword: password,
    );
    if (!mounted) return;
    _disposeRowControllers();
    setState(() {
      _busy = false;
      _rows = List.of(result.rows);
      _rebuildRowControllers();
      final fileLevel = result.rows.isNotEmpty && result.rows.first.row == 0;
      _batchError = fileLevel && result.rows.first.errors.isNotEmpty
          ? result.rows.first.errors['name']
          : null;
      if (_batchError == null) {
        _phase = _BulkPhase.review;
      }
    });
  }

  Future<void> _revalidate() async {
    _readControllersIntoRows();
    setState(() => _busy = true);
    final password = _passwordController.text.trim();
    final result = await BulkStudentsService().validateRows(
      rows: _rows,
      defaultPassword: password,
    );
    if (!mounted) return;
    _disposeRowControllers();
    setState(() {
      _busy = false;
      _rows = List.of(result.rows);
      _rebuildRowControllers();
    });
  }

  Future<void> _createStudents() async {
    _readControllersIntoRows();
    setState(() => _busy = true);
    final result = await BulkStudentsService().createBulk(
      rows: _rows,
      defaultPassword: _passwordController.text.trim(),
    );
    if (!mounted) return;
    final success = result['success'] == true;
    Navigator.of(context).pop();
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result['created'] ?? 0} students added successfully'),
          backgroundColor: DialogColors.tealDark,
        ),
      );
      widget.onStudentCreated();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to add students'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _readControllersIntoRows() {
    for (var i = 0; i < _rows.length && i < _nameControllers.length; i++) {
      _rows[i].name = _nameControllers[i].text.trim();
      _rows[i].email = _emailControllers[i].text.trim().toLowerCase();
      _rows[i].semester = _semesterControllers[i].text.trim();
    }
  }

  void _rebuildRowControllers() {
    for (final row in _rows) {
      _nameControllers.add(TextEditingController(text: row.name));
      _emailControllers.add(TextEditingController(text: row.email));
      _semesterControllers.add(TextEditingController(text: row.semester));
    }
  }
}
