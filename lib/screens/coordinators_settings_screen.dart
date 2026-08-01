import 'package:flutter/material.dart';

import '../models/coordinator.dart';
import '../services/coordinator_service.dart';
import '../theme/app_theme.dart';

class CoordinatorsSettingsScreen extends StatefulWidget {
  /// أزواج (شطر، قسم) المستخرجة من آخر ملف مستورد، لعرض حقل لكل قسم فعلي
  final List<MapEntry<String, String>> shatrDepartmentPairs;

  const CoordinatorsSettingsScreen({
    super.key,
    required this.shatrDepartmentPairs,
  });

  @override
  State<CoordinatorsSettingsScreen> createState() =>
      _CoordinatorsSettingsScreenState();
}

class _CoordinatorsSettingsScreenState
    extends State<CoordinatorsSettingsScreen> {
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, TextEditingController> _emailControllers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await CoordinatorService.loadAll();

    for (final pair in widget.shatrDepartmentPairs) {
      final key = '${pair.key}|${pair.value}';
      final existing = saved[key];
      _nameControllers[key] = TextEditingController(text: existing?.name ?? '');
      _emailControllers[key] = TextEditingController(
        text: existing?.email ?? '',
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveAll() async {
    final updated = <String, Coordinator>{};
    for (final pair in widget.shatrDepartmentPairs) {
      final key = '${pair.key}|${pair.value}';
      updated[key] = Coordinator(
        shatr: pair.key,
        department: pair.value,
        name: _nameControllers[key]!.text.trim(),
        email: _emailControllers[key]!.text.trim(),
      );
    }

    await CoordinatorService.saveAll(updated);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ بيانات المنسقين')));
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _emailControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات منسقي الأقسام'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'حفظ',
            onPressed: _isLoading ? null : _saveAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.shatrDepartmentPairs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'استورد ملف Excel أولاً حتى تظهر لك أقسام الشطرين هنا',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.shatrDepartmentPairs.length,
              itemBuilder: (context, index) {
                final pair = widget.shatrDepartmentPairs[index];
                final key = '${pair.key}|${pair.value}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.green.withValues(
                                alpha: 0.12,
                              ),
                              child: const Icon(
                                Icons.apartment_outlined,
                                size: 15,
                                color: AppColors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${pair.value.isEmpty ? '(بدون قسم)' : pair.value} — ${pair.key}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameControllers[key],
                          decoration: const InputDecoration(
                            labelText: 'اسم المنسّق/المنسّقة',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _emailControllers[key],
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: widget.shatrDepartmentPairs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isLoading ? null : _saveAll,
              icon: const Icon(Icons.save),
              label: const Text('حفظ البيانات'),
            ),
    );
  }
}
