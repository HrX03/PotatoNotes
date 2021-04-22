import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/internal/backup_restore.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class BackupPage extends StatefulWidget {
  @override
  _BackupPageState createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final List<Note> notes = [];
  String name = "";

  @override
  void initState() {
    super.initState();
    _initNotes();
  }

  Future<void> _initNotes() async {
    notes.addAll(await helper.listNotes(ReturnMode.local));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Create backup",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(
                MdiIcons.zipBox,
                size: 64,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: "Backup name (optional)",
                  ),
                  maxLength: 64,
                  onChanged: (value) {
                    name = value;
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Notes to be included in backup: ${notes.length}",
            style: TextStyle(
              color: context.theme.iconTheme.color,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final bool promptForPassword = notes.any((n) => n.lockNote);
                  final bool promptForBiometrics = notes.any((n) => n.lockNote);
                  bool status = true;
                  if (promptForPassword) {
                    status = await Utils.showNoteLockDialog(
                      context: context,
                      showLock: promptForPassword,
                      showBiometrics: promptForBiometrics,
                      description:
                          "Some notes are locked, require password. Note: backup won't be locked.",
                    );
                  }
                  if (status) {
                    Navigator.pop(context);
                    Utils.showNotesModalBottomSheet(
                      context: context,
                      builder: (context) => _BackupProgressPage(
                        notes: notes,
                        name: name.trim() != "" ? name : null,
                      ),
                      enableDismiss: false,
                    );
                  }
                },
                child: Text("Create".toUpperCase()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackupProgressPage extends StatefulWidget {
  final List<Note> notes;
  final String? name;

  const _BackupProgressPage({
    required this.notes,
    this.name,
  });

  @override
  _BackupProgressPageState createState() => _BackupProgressPageState();
}

class _BackupProgressPageState extends State<_BackupProgressPage> {
  int currentNote = 0;

  @override
  void initState() {
    super.initState();
    _startBackup();
  }

  Future<void> _startBackup() async {
    final File backup = await BackupRestore.createBackup(
      notes: widget.notes,
      name: widget.name,
      onProgress: (value) => setState(() => currentNote = value),
    );
    Navigator.pop(context);
    Utils.showNotesModalBottomSheet(
      context: context,
      builder: (context) => _BackupCompletePage(
        backupFile: backup,
      ),
      enableDismiss: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Generating backup",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text("Backing up note $currentNote of ${widget.notes.length}"),
          trailing: const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }
}

class _BackupCompletePage extends StatelessWidget {
  final File backupFile;

  const _BackupCompletePage({
    required this.backupFile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Backup completed successfully!",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                    text:
                        "The backup process was a success! You can find the backup at "),
                TextSpan(
                  text: backupFile.path,
                  style: TextStyle(
                    color: context.theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launch(backupFile.parent.path),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text("Close".toUpperCase()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}