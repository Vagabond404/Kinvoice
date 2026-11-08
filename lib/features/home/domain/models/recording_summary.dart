import 'package:flutter/foundation.dart';

/// Immutable domain model representing a voice recording summary in the Kinvoice timeline.
@immutable
class RecordingSummary {
  const RecordingSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationSeconds,
    required this.transcriptSnippet,
    required this.speakers,
    required this.tags,
    required this.isFavorite,
    required this.audioFilePath,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int durationSeconds;
  final String transcriptSnippet;
  final List<String> speakers;
  final List<String> tags;
  final bool isFavorite;
  final String audioFilePath;

  /// Formats the duration in seconds to standard 'mm:ss' representation.
  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }

  /// Generates a readable relative or absolute timestamp label for display.
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    if (difference.inDays == 0 && createdAt.day == now.day) {
      return 'Today, $timeStr';
    } else if (difference.inDays <= 1) {
      return 'Yesterday, $timeStr';
    } else {
      final month = createdAt.month.toString().padLeft(2, '0');
      final day = createdAt.day.toString().padLeft(2, '0');
      return '$day/$month, $timeStr';
    }
  }

  /// Returns a copy of this summary with updated values.
  RecordingSummary copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    int? durationSeconds,
    String? transcriptSnippet,
    List<String>? speakers,
    List<String>? tags,
    bool? isFavorite,
    String? audioFilePath,
  }) {
    return RecordingSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      transcriptSnippet: transcriptSnippet ?? this.transcriptSnippet,
      speakers: speakers ?? this.speakers,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      audioFilePath: audioFilePath ?? this.audioFilePath,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecordingSummary &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.durationSeconds == durationSeconds &&
        other.transcriptSnippet == transcriptSnippet &&
        listEquals(other.speakers, speakers) &&
        listEquals(other.tags, tags) &&
        other.isFavorite == isFavorite &&
        other.audioFilePath == audioFilePath;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    createdAt,
    durationSeconds,
    transcriptSnippet,
    Object.hashAll(speakers),
    Object.hashAll(tags),
    isFavorite,
    audioFilePath,
  );

  @override
  String toString() {
    return 'RecordingSummary(id: $id, title: $title, duration: $formattedDuration, favorite: $isFavorite)';
  }
}
