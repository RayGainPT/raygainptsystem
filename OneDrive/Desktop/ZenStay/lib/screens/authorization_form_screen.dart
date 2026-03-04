import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/authorization_model.dart';
import '../models/guest_model.dart';
import '../services/authorization_pdf_service.dart';

class AuthorizationFormScreen extends StatefulWidget {
  const AuthorizationFormScreen({Key? key}) : super(key: key);

  @override
  State<AuthorizationFormScreen> createState() => _AuthorizationFormScreenState();
}

class _AuthorizationFormScreenState extends State<AuthorizationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _towerCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _unitOwnerNameCtrl = TextEditingController();

  /// Signature image (PNG/JPG) bytes for the PDF. Null until user uploads.
  Uint8List? _signatureImageBytes;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now().add(const Duration(days: 1));
  DateTime _givenThisDayDate = DateTime.now();

  final List<GuestModel> _guests = [];
  final List<GlobalKey<_GuestRowState>> _guestRowKeys = [];
  static const int _maxGuests = AuthorizationModel.maxGuests;

  final AuthorizationPdfService _pdfService = AuthorizationPdfService();

  @override
  void dispose() {
    _towerCtrl.dispose();
    _unitCtrl.dispose();
    _unitOwnerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSignatureImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() => _signatureImageBytes = bytes);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read the image. Try another file.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _pickGivenThisDayDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _givenThisDayDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (d != null) setState(() => _givenThisDayDate = d);
  }

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (d != null) setState(() => _fromDate = d);
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (d != null) setState(() => _toDate = d);
  }

  void _addGuest() {
    if (_guests.length >= _maxGuests) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum $_maxGuests guests allowed.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _guests.add(const GuestModel(name: '', proofOfId: '', relationship: ''));
      _guestRowKeys.add(GlobalKey<_GuestRowState>());
    });
  }

  void _removeGuest(int index) {
    setState(() {
      _guests.removeAt(index);
      _guestRowKeys.removeAt(index);
    });
  }

  void _ensureGuestRowKeys() {
    while (_guestRowKeys.length < _guests.length) {
      _guestRowKeys.add(GlobalKey<_GuestRowState>());
    }
    while (_guestRowKeys.length > _guests.length) {
      _guestRowKeys.removeLast();
    }
  }

  /// Collects current guest data from each row (so PDF gets latest even if user didn't tab out).
  List<GuestModel> _getGuestsForPdf() {
    _ensureGuestRowKeys();
    final List<GuestModel> result = [];
    for (int i = 0; i < _guests.length; i++) {
      final rowState = i < _guestRowKeys.length ? _guestRowKeys[i].currentState : null;
      result.add(rowState?.currentGuest ?? _guests[i]);
    }
    return result;
  }

  Future<void> _generatePdf() async {
    if (!_formKey.currentState!.validate()) return;

    // Unfocus so any focused guest field commits (onEditingComplete fires).
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 100));

    if (_guests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one guest.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final tower = _towerCtrl.text.trim();
    final unit = _unitCtrl.text.trim();
    final unitOwnerName = _unitOwnerNameCtrl.text.trim();
    if (tower.isEmpty || unit.isEmpty || unitOwnerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill Tower, Unit, and Unit Owner Name.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final data = AuthorizationModel(
      tower: tower,
      unit: unit,
      fromDate: _fromDate,
      toDate: _toDate,
      unitOwnerName: unitOwnerName,
      givenThisDayDate: _givenThisDayDate,
      signatureImageBytes: _signatureImageBytes,
      ownerSignature: '',
      guests: _getGuestsForPdf(),
    );

    try {
      final bytes = await _pdfService.generateAuthorizationPdf(data);
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Authorization_Letter_${DateFormat('yyyyMMdd').format(_fromDate)}.pdf',
      );
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Invalid input.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureGuestRowKeys();
    final dateFormat = DateFormat('MMM dd, yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text('Authorization Letter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Fill the form and generate a flattened PDF for the condominium association.',
                style: GoogleFonts.poppins(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _towerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tower',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Tower A',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _unitCtrl,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 12B',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickFromDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'From Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(dateFormat.format(_fromDate), style: GoogleFonts.poppins()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: _pickToDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'To Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(dateFormat.format(_toDate), style: GoogleFonts.poppins()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _unitOwnerNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Unit Owner Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickGivenThisDayDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Given this day (date for letter)',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(dateFormat.format(_givenThisDayDate), style: GoogleFonts.poppins()),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Owner signature (image)',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickSignatureImage,
                    icon: const Icon(Icons.upload_file, size: 20),
                    label: const Text('Upload signature image'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF008080),
                      side: const BorderSide(color: Color(0xFF008080)),
                    ),
                  ),
                  if (_signatureImageBytes != null) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _signatureImageBytes!,
                              height: 80,
                              width: 200,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => setState(() => _signatureImageBytes = null),
                            child: Text('Remove', style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (_signatureImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Signature image will appear in the PDF. Use PNG or JPG.',
                    style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 12),
                ),
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Guests (max $_maxGuests)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
                  TextButton.icon(
                    onPressed: _guests.length >= _maxGuests ? null : _addGuest,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Guest'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...List.generate(_guests.length, (index) => _GuestRow(
                key: _guestRowKeys[index],
                guest: _guests[index],
                index: index,
                onChanged: (g) => setState(() => _guests[index] = g),
                onRemove: () => _removeGuest(index),
              )),
              if (_guests.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No guests added. Tap "Add Guest" to add up to $_maxGuests guests.',
                    style: GoogleFonts.poppins(color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _guests.isEmpty ? null : _generatePdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Generate PDF'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF008080),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestRow extends StatefulWidget {
  final GuestModel guest;
  final int index;
  final ValueChanged<GuestModel> onChanged;
  final VoidCallback onRemove;

  const _GuestRow({
    super.key,
    required this.guest,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_GuestRow> createState() => _GuestRowState();
}

class _GuestRowState extends State<_GuestRow> {
  late TextEditingController _nameCtrl;
  late TextEditingController _proofCtrl;
  late TextEditingController _relationCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.guest.name);
    _proofCtrl = TextEditingController(text: widget.guest.proofOfId);
    _relationCtrl = TextEditingController(text: widget.guest.relationship);
  }

  @override
  void didUpdateWidget(_GuestRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync from parent when the guest at this index was replaced from outside
    // (e.g. list reorder). Do NOT overwrite on every rebuild or we wipe what the user is typing.
    if (oldWidget.index != widget.index ||
        oldWidget.guest.name != widget.guest.name ||
        oldWidget.guest.proofOfId != widget.guest.proofOfId ||
        oldWidget.guest.relationship != widget.guest.relationship) {
      _nameCtrl.text = widget.guest.name;
      _proofCtrl.text = widget.guest.proofOfId;
      _relationCtrl.text = widget.guest.relationship;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _proofCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(GuestModel(
      name: _nameCtrl.text.trim(),
      proofOfId: _proofCtrl.text.trim(),
      relationship: _relationCtrl.text.trim(),
    ));
  }

  /// Current field values for PDF generation (avoids relying on onEditingComplete).
  GuestModel get currentGuest => GuestModel(
    name: _nameCtrl.text.trim(),
    proofOfId: _proofCtrl.text.trim(),
    relationship: _relationCtrl.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Guest ${widget.index + 1}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true),
              onEditingComplete: _notify,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _proofCtrl,
              decoration: const InputDecoration(labelText: 'Proof of ID', border: OutlineInputBorder(), isDense: true),
              onEditingComplete: _notify,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _relationCtrl,
              decoration: const InputDecoration(labelText: 'Relationship', border: OutlineInputBorder(), isDense: true),
              onEditingComplete: _notify,
            ),
          ],
        ),
      ),
    );
  }
}
