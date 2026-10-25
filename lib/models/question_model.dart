import 'package:cloud_firestore/cloud_firestore.dart';

/// Public projection of a question — no answer key.
class QuestionModel {
  final String id;
  final String stem;
  final List<QuestionOption> options;
  final QuestionContext? context;
  final String domain;
  final String difficulty;
  final List<String> tags;

  QuestionModel({
    required this.id,
    required this.stem,
    required this.options,
    this.context,
    required this.domain,
    required this.difficulty,
    required this.tags,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json, String id) {
    return QuestionModel(
      id: id,
      stem: json['stem'] ?? '',
      options: (json['options'] as List<dynamic>? ?? [])
          .map((o) => QuestionOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      context: json['context'] != null
          ? QuestionContext.fromJson(json['context'] as Map<String, dynamic>)
          : null,
      domain: json['domain'] ?? 'General',
      difficulty: json['difficulty'] ?? 'medium',
      tags: List<String>.from(json['tags'] ?? []),
    );
  }
}

class QuestionOption {
  final String id;
  final String text;

  QuestionOption({required this.id, required this.text});

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

class QuestionContext {
  final List<VitalEntry>? vitals;
  final String? imageUrl;

  QuestionContext({this.vitals, this.imageUrl});

  factory QuestionContext.fromJson(Map<String, dynamic> json) {
    return QuestionContext(
      vitals: (json['vitals'] as List<dynamic>?)
          ?.map((v) => VitalEntry.fromJson(v as Map<String, dynamic>))
          .toList(),
      imageUrl: json['imageUrl'],
    );
  }
}

class VitalEntry {
  final String label;
  final String value;

  VitalEntry({required this.label, required this.value});

  factory VitalEntry.fromJson(Map<String, dynamic> json) {
    return VitalEntry(
      label: json['label'] ?? '',
      value: json['value'] ?? '',
    );
  }
}
