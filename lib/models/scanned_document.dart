import 'dart:convert';

class ScannedDocument {
  final String id;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final int pageCount;
  final int fileSize;
  final bool isPdf;

  ScannedDocument({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.pageCount,
    required this.fileSize,
    required this.isPdf,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.toIso8601String(),
      'pageCount': pageCount,
      'fileSize': fileSize,
      'isPdf': isPdf,
    };
  }

  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    return ScannedDocument(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      createdAt: DateTime.parse(json['createdAt']),
      pageCount: json['pageCount'],
      fileSize: json['fileSize'],
      isPdf: json['isPdf'],
    );
  }

  String get extension => isPdf ? 'pdf' : 'jpg';

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024)
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${createdAt.month} ${createdAt.day}';
    }
  }
}
