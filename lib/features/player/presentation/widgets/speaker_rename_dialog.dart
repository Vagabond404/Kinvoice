import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Dialog allowing users to rename a detected speaker (e.g., "Speaker 1" -> "Ange")
/// across all segments in a recording.
class SpeakerRenameDialog extends StatefulWidget {
  const SpeakerRenameDialog({
    super.key,
    required this.currentSpeakerName,
  });

  final String currentSpeakerName;

  static Future<String?> show(
    BuildContext context, {
    required String currentSpeakerName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => SpeakerRenameDialog(
        currentSpeakerName: currentSpeakerName,
      ),
    );
  }

  @override
  State<SpeakerRenameDialog> createState() => _SpeakerRenameDialogState();
}

class _SpeakerRenameDialogState extends State<SpeakerRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentSpeakerName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            'Rename Speaker',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change "${widget.currentSpeakerName}" across all segments in this conversation:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter speaker name...',
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceContainerDark
                  : AppColors.surfaceContainerLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final newName = _controller.text.trim();
            if (newName.isNotEmpty) {
              Navigator.pop(context, newName);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
