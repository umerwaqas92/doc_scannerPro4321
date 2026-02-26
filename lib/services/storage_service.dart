import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scanned_document.dart';

class StorageService {
  static const String _documentsKey = 'scanned_documents';

  Future<String> get _documentsPath async {
    final directory = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${directory.path}/scanned_docs');
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    return docsDir.path;
  }

  Future<List<ScannedDocument>> getDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_documentsKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((e) => ScannedDocument.fromJson(e)).toList();
  }

  Future<void> saveDocument(ScannedDocument document) async {
    final documents = await getDocuments();
    documents.insert(0, document);
    await _saveDocumentsList(documents);
  }

  Future<void> deleteDocument(String id) async {
    final documents = await getDocuments();
    final docToDelete = documents.firstWhere((d) => d.id == id);

    final file = File(docToDelete.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    documents.removeWhere((d) => d.id == id);
    await _saveDocumentsList(documents);
  }

  Future<void> _saveDocumentsList(List<ScannedDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = documents.map((d) => d.toJson()).toList();
    await prefs.setString(_documentsKey, json.encode(jsonList));
  }

  Future<String> getDocumentsDirectory() async {
    return await _documentsPath;
  }

  Future<File> saveImageToDocuments(String sourcePath, String fileName) async {
    final docsPath = await _documentsPath;
    final newPath = '$docsPath/$fileName';
    final sourceFile = File(sourcePath);
    return await sourceFile.copy(newPath);
  }
}
