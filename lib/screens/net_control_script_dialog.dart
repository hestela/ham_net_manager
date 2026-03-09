import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';

const defaultNetControlScript = '''# Net Control Script

Welcome to the **{net_name}** net.

My name is **{user_first_name} {user_last_name}**, callsign **{user_callsign}**.

---

*Edit this script using the pencil button above.*
''';

/// A side panel widget for displaying / editing the net control script.
class NetControlScriptPanel extends StatefulWidget {
  final VoidCallback onClose;
  const NetControlScriptPanel({super.key, required this.onClose});

  @override
  State<NetControlScriptPanel> createState() => _NetControlScriptPanelState();
}

class _NetControlScriptPanelState extends State<NetControlScriptPanel> {
  bool _editing = false;
  bool _loading = true;
  String _rawScript = '';
  late TextEditingController _editController;
  Map<String, String> _templateVars = {};

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _loadScript();
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _loadScript() async {
    final script = await DatabaseHelper.getSetting('net_control_script') ??
        defaultNetControlScript;
    final prefs = await SharedPreferences.getInstance();
    _templateVars = {
      'user_first_name': prefs.getString('user_first_name') ?? '',
      'user_last_name': prefs.getString('user_last_name') ?? '',
      'user_callsign': prefs.getString('user_callsign') ?? '',
      'net_name': DatabaseHelper.currentCity,
    };
    setState(() {
      _rawScript = script;
      _loading = false;
    });
  }

  String _applyTemplate(String source) {
    var result = source;
    for (final entry in _templateVars.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  Future<void> _save() async {
    final text = _editController.text;
    await DatabaseHelper.setSetting('net_control_script', text);
    setState(() {
      _rawScript = text;
      _editing = false;
    });
  }

  void _startEditing() {
    _editController.text = _rawScript;
    setState(() => _editing = true);
  }

  void _cancelEditing() {
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade400)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        children: [
          // Title bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.inversePrimary,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Net Control Script',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  tooltip: 'Help',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _TemplateHelpDialog(),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (!_editing)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Edit script',
                    onPressed: _loading ? null : _startEditing,
                    visualDensity: VisualDensity.compact,
                  ),
                if (_editing) ...[
                  TextButton(
                    onPressed: _cancelEditing,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 2),
                  FilledButton.icon(
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save'),
                    onPressed: _save,
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _editing
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: TextField(
                          controller: _editController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 14),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Write your script in Markdown…',
                          ),
                        ),
                      )
                    : Markdown(
                        data: _applyTemplate(_rawScript),
                        padding: const EdgeInsets.all(14),
                        styleSheet: MarkdownStyleSheet(
                          h1: const TextStyle(fontSize: 22),
                          p: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _TemplateHelpDialog extends StatelessWidget {
  const _TemplateHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Net Control Script Help'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The script is written in Markdown. You can use headings, '
              'bold, italics, lists, tables, and other Markdown formatting.',
            ),
            const SizedBox(height: 12),
            const Text(
              'You can also use these template variables, which will be '
              'replaced with their values when rendered:',
            ),
            const SizedBox(height: 16),
            _row('{user_first_name}', 'Your first name (from Your Info)'),
            _row('{user_last_name}', 'Your last name (from Your Info)'),
            _row('{user_callsign}', 'Your callsign (from Your Info)'),
            _row('{net_name}', 'Current net / city name'),
            const SizedBox(height: 12),
            const Text(
              'Set your name and callsign from the hamburger menu → Your Info',
              style: TextStyle(fontSize: 13, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const SelectableText(
                'Example:\n'
                'Good evening, this is the **{net_name}** weekly net.\n'
                'My name is **{user_first_name}**, **{user_callsign}**.',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }

  static Widget _row(String variable, String description) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: SelectableText(
                variable,
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(description,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ),
          ],
        ),
      );
}
