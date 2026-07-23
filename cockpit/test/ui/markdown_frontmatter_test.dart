import 'package:cockpit/app/core/ui/widgets/markdown_frontmatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

// Garante que o frontmatter (portado do fork do gpt_markdown — PR #139) segue
// funcionando após a volta do pacote pro pub.dev: o split tira o bloco `---`
// do corpo e a tabela renderiza os campos.
void main() {
  const skillMd = '''
---
name: code-reviewer
description: Reviews diffs for bugs.
tags:
  - review
  - quality
---

# Code Reviewer

Body text.
''';

  group('MarkdownFrontmatter.split', () {
    test('extrai campos e remove o bloco do corpo', () {
      final split = MarkdownFrontmatter.split(skillMd);
      final fm = split.frontmatter;
      expect(fm, isNotNull);
      expect(fm!.string('name'), 'code-reviewer');
      expect(fm.string('description'), 'Reviews diffs for bugs.');
      expect(fm.stringList('tags'), ['review', 'quality']);
      expect(split.body, isNot(contains('name:')));
      expect(split.body, contains('# Code Reviewer'));
    });

    test('documento sem frontmatter passa intacto', () {
      const doc = '# Título\n\ntexto';
      final split = MarkdownFrontmatter.split(doc);
      expect(split.frontmatter, isNull);
      expect(split.body, doc);
    });

    test('duas HRs adjacentes não viram frontmatter', () {
      const doc = '---\n\n---\ncorpo';
      expect(MarkdownFrontmatter.split(doc).frontmatter, isNull);
    });
  });

  testWidgets('MarkdownFrontmatterTable renderiza chaves e valores', (
    tester,
  ) async {
    final fm = MarkdownFrontmatter.split(skillMd).frontmatter!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownFrontmatterTable(frontmatter: fm),
        ),
      ),
    );
    expect(find.text('name'), findsOneWidget);
    expect(find.text('code-reviewer'), findsOneWidget);
    expect(find.text('description'), findsOneWidget);
    expect(find.textContaining('review'), findsWidgets);
  });

  testWidgets('GptMarkdown do pub.dev não engole o corpo pós-split', (
    tester,
  ) async {
    final split = MarkdownFrontmatter.split(skillMd);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GptMarkdown(split.body.trim())),
      ),
    );
    expect(find.textContaining('Code Reviewer'), findsWidgets);
  });
}
